import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../errors.dart';
import '../ffmpeg/ffmpeg_binaries.dart';
import '../ffmpeg/ffmpeg_commands.dart';
import '../ffmpeg/ffmpeg_progress_parser.dart';
import '../ffmpeg/ffprobe_parser.dart';
import '../models/clip_candidate.dart';
import '../models/media_info.dart';
import '../models/processing_job.dart';
import '../models/requests.dart';
import '../models/transcript.dart';
import '../video_engine.dart';

/// Desktop engine that drives the FFmpeg and FFprobe executables.
///
/// Every job writes to `<output>.part` and is renamed into place only after
/// FFmpeg exits successfully, so a crash, failure or cancel never leaves a
/// truncated file at the requested output path.
class WindowsVideoEngine implements VideoEngine {
  WindowsVideoEngine({FfmpegBinaries? binaries, this.preferredVideoEncoder})
    : binaries = binaries ?? FfmpegBinaries.locate();

  final FfmpegBinaries binaries;

  /// Forces a specific H.264 encoder instead of the first available one.
  final String? preferredVideoEncoder;

  /// How long a cancelled FFmpeg may take to exit on its own before it is
  /// killed.
  static const _gracefulStop = Duration(seconds: 3);
  static const _stderrTailLines = 30;
  static const _uuid = Uuid();
  static const _decoder = Utf8Decoder(allowMalformed: true);

  final _jobs = <String, ProcessingJob>{};
  final _running = <String, Process>{};
  final _cancelRequested = <String>{};
  final _updates = StreamController<ProcessingJob>.broadcast();
  Future<_Toolchain>? _toolchain;
  bool _disposed = false;

  @override
  Stream<ProcessingJob> get jobUpdates => _updates.stream;

  @override
  ProcessingJob? jobStatus(String jobId) => _jobs[jobId];

  @override
  Future<EngineCapabilities> capabilities() async {
    try {
      final toolchain = await _loadToolchain();
      return EngineCapabilities(
        platform: Platform.operatingSystem,
        canInspect: true,
        canExtractAudio: true,
        canRender: toolchain.videoEncoder != null,
        canTranscribe: false,
        canDetectHighlights: false,
        ffmpegVersion: toolchain.version,
        videoEncoder: toolchain.videoEncoder,
        isGplBuild: toolchain.isGplBuild,
        unavailableReason: toolchain.videoEncoder == null
            ? 'This FFmpeg build has no supported H.264 encoder '
                  '(${supportedH264Encoders.join(', ')})'
            : null,
      );
    } on EngineUnavailableException catch (e) {
      return EngineCapabilities(
        platform: Platform.operatingSystem,
        canInspect: false,
        canExtractAudio: false,
        canRender: false,
        canTranscribe: false,
        canDetectHighlights: false,
        unavailableReason: e.message,
      );
    }
  }

  @override
  Future<MediaInfo> inspect(String sourcePath) async {
    if (!File(sourcePath).existsSync()) {
      throw MediaNotFoundException(sourcePath);
    }
    final result = await _runTool(
      binaries.ffprobe,
      ffprobeArguments(sourcePath),
    );
    if (result.exitCode != 0) {
      throw InvalidMediaException(
        'Could not read this file as media',
        details: '${result.stderr}'.trim(),
      );
    }
    final info = parseFfprobeJson('${result.stdout}', path: sourcePath);
    if (!info.hasVideo && !info.hasAudio) {
      throw const InvalidMediaException('File contains no audio or video');
    }
    return info;
  }

  @override
  EngineJob<String> extractAudio(AudioExtractionRequest request) => _start(
    type: JobType.audioExtraction,
    sourcePath: request.sourcePath,
    outputPath: request.outputPath,
    prepare: (partialPath) async {
      final media = await inspect(request.sourcePath);
      return _Plan(
        arguments: audioExtractionArguments(
          request,
          media,
          outputPath: partialPath,
        ),
        totalMs: audioExtractionDurationMs(request, media),
        result: request.outputPath,
      );
    },
  );

  @override
  EngineJob<String> generateThumbnail(ThumbnailRequest request) => _start(
    type: JobType.thumbnail,
    sourcePath: request.sourcePath,
    outputPath: request.outputPath,
    prepare: (partialPath) async => _Plan(
      arguments: thumbnailArguments(request, outputPath: partialPath),
      totalMs: 0,
      result: request.outputPath,
    ),
  );

  @override
  EngineJob<RenderResult> renderClip(RenderRequest request) => _start(
    type: JobType.render,
    sourcePath: request.sourcePath,
    outputPath: request.outputPath,
    prepare: (partialPath) async {
      final toolchain = await _loadToolchain();
      final encoder = toolchain.videoEncoder;
      if (encoder == null) {
        throw EngineUnavailableException(
          'This FFmpeg build has no supported H.264 encoder '
          '(${supportedH264Encoders.join(', ')})',
        );
      }
      final media = request.mediaInfo ?? await inspect(request.sourcePath);
      final plan = planRender(
        request,
        media,
        videoEncoder: encoder,
        outputPath: partialPath,
      );
      return _Plan(
        arguments: plan.arguments,
        totalMs: plan.durationMs,
        result: RenderResult(
          outputPath: request.outputPath,
          width: plan.outputWidth,
          height: plan.outputHeight,
          durationMs: plan.durationMs,
          videoEncoder: encoder,
        ),
      );
    },
  );

  @override
  EngineJob<Transcript> transcribe(TranscriptionRequest request) =>
      throw const EngineUnsupportedException(
        'Local transcription is not integrated yet (whisper.cpp milestone)',
      );

  @override
  Future<List<ClipCandidate>> detectHighlights(
    HighlightRequest request,
  ) async => throw const EngineUnsupportedException(
    'Offline highlight detection is not implemented yet',
  );

  @override
  Future<void> cancel(String jobId) async {
    final job = _jobs[jobId];
    if (job == null || job.status.isTerminal) return;
    _cancelRequested.add(jobId);
    final process = _running[jobId];
    if (process == null) return; // Still preparing; _run checks the flag.
    try {
      // "q" asks FFmpeg to stop cleanly and release its file handles.
      process.stdin.write('q');
      await process.stdin.flush();
    } on Object {
      // stdin already closed; fall through to the kill below.
    }
    await process.exitCode.timeout(
      _gracefulStop,
      onTimeout: () {
        process.kill();
        return process.exitCode;
      },
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait([for (final id in _running.keys.toList()) cancel(id)]);
    await _updates.close();
  }

  EngineJob<T> _start<T>({
    required JobType type,
    required String sourcePath,
    required String outputPath,
    required Future<_Plan<T>> Function(String partialPath) prepare,
  }) {
    if (_disposed) {
      throw const EngineUnavailableException('Engine has been disposed');
    }
    final id = _uuid.v4();
    final progress = StreamController<RenderProgress>.broadcast();
    final completer = Completer<T>();
    // Callers that only watch jobUpdates never listen to the result.
    completer.future.ignore();
    _setJob(
      ProcessingJob(
        id: id,
        type: type,
        status: JobStatus.queued,
        createdAt: DateTime.now(),
        outputPath: outputPath,
      ),
    );
    unawaited(_run(id, sourcePath, outputPath, prepare, progress, completer));
    return EngineJob(
      id: id,
      progress: progress.stream,
      result: completer.future,
    );
  }

  Future<void> _run<T>(
    String id,
    String sourcePath,
    String outputPath,
    Future<_Plan<T>> Function(String partialPath) prepare,
    StreamController<RenderProgress> progress,
    Completer<T> completer,
  ) async {
    final partial = File('$outputPath.part');
    try {
      if (!File(sourcePath).existsSync()) {
        throw MediaNotFoundException(sourcePath);
      }
      await Directory(p.dirname(p.absolute(outputPath)))
          .create(recursive: true);
      final plan = await prepare(partial.path);
      if (_cancelRequested.contains(id)) throw JobCancelledException(id);

      final Process process;
      try {
        process = await Process.start(binaries.ffmpeg, plan.arguments);
      } on ProcessException catch (e) {
        throw EngineUnavailableException(
          'FFmpeg could not be started',
          details: e.message,
        );
      }
      _running[id] = process;
      process.stdin.done.ignore();
      _setJob(_jobs[id]!.copyWith(status: JobStatus.running));

      final stderrTail = <String>[];
      final stderrDone = process.stderr
          .transform(_decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            stderrTail.add(line);
            if (stderrTail.length > _stderrTailLines) stderrTail.removeAt(0);
          });
      final parser = FfmpegProgressParser(totalMs: plan.totalMs);
      final stdoutDone = process.stdout
          .transform(_decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            final update = parser.addLine(line);
            if (update == null) return;
            progress.add(update);
            _setJob(_jobs[id]!.copyWith(progress: update));
          });

      final exitCode = await process.exitCode;
      await Future.wait([stderrDone, stdoutDone]);

      if (_cancelRequested.contains(id)) throw JobCancelledException(id);
      if (exitCode != 0) {
        throw ProcessingFailedException(
          'FFmpeg exited with code $exitCode',
          details: stderrTail.join('\n'),
          exitCode: exitCode,
        );
      }
      if (!partial.existsSync() || partial.lengthSync() == 0) {
        throw ProcessingFailedException(
          'FFmpeg produced no output',
          details: stderrTail.join('\n'),
        );
      }
      final target = File(outputPath);
      if (target.existsSync()) await target.delete();
      await partial.rename(outputPath);

      _finish(id, JobStatus.completed);
      completer.complete(plan.result);
    } on Object catch (error, stackTrace) {
      await _deleteQuietly(partial);
      final EngineException failure = switch (error) {
        EngineException() => error,
        FileSystemException() => ProcessingFailedException(
          'Could not write the output file',
          details: error.message,
        ),
        _ => ProcessingFailedException(
          'Unexpected engine error',
          details: '$error',
        ),
      };
      _finish(
        id,
        failure is JobCancelledException
            ? JobStatus.cancelled
            : JobStatus.failed,
        errorMessage: failure is JobCancelledException ? null : failure.message,
      );
      completer.completeError(failure, stackTrace);
    } finally {
      _running.remove(id);
      _cancelRequested.remove(id);
      await progress.close();
    }
  }

  void _finish(String id, JobStatus status, {String? errorMessage}) => _setJob(
    _jobs[id]!.copyWith(
      status: status,
      errorMessage: errorMessage,
      finishedAt: DateTime.now(),
    ),
  );

  void _setJob(ProcessingJob job) {
    _jobs[job.id] = job;
    if (!_updates.isClosed) _updates.add(job);
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Best effort: a leftover .part file is harmless and is overwritten by
      // the next job that targets the same output.
    }
  }

  Future<ProcessResult> _runTool(
    String executable,
    List<String> arguments,
  ) async {
    try {
      return await Process.run(
        executable,
        arguments,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } on ProcessException catch (e) {
      throw EngineUnavailableException(
        '${p.basename(executable)} was not found. Install FFmpeg or set '
        '${FfmpegBinaries.directoryVariable}.',
        details: e.message,
      );
    }
  }

  Future<_Toolchain> _loadToolchain() =>
      _toolchain ??= _probeToolchain().onError<Object>((error, stackTrace) {
        _toolchain = null; // Allow a retry once the tools are installed.
        Error.throwWithStackTrace(error, stackTrace);
      });

  Future<_Toolchain> _probeToolchain() async {
    final version = await _runTool(binaries.ffmpeg, [
      '-hide_banner',
      '-version',
    ]);
    final encoders = await _runTool(binaries.ffmpeg, [
      '-hide_banner',
      '-encoders',
    ]);
    if (version.exitCode != 0 || encoders.exitCode != 0) {
      throw EngineUnavailableException(
        'FFmpeg did not start correctly',
        details: '${version.stderr}'.trim(),
      );
    }
    final versionText = '${version.stdout}';
    final available = {
      for (final line in const LineSplitter().convert('${encoders.stdout}'))
        if (line.trim().split(RegExp(r'\s+')) case [_, final name, ...]) name,
    };
    final preferred = preferredVideoEncoder;
    return _Toolchain(
      version: RegExp(r'ffmpeg version (\S+)')
          .firstMatch(versionText)
          ?.group(1),
      isGplBuild: versionText.contains('--enable-gpl'),
      videoEncoder: preferred != null
          ? (available.contains(preferred) ? preferred : null)
          : supportedH264Encoders.where(available.contains).firstOrNull,
    );
  }
}

class _Toolchain {
  const _Toolchain({
    required this.version,
    required this.isGplBuild,
    required this.videoEncoder,
  });

  final String? version;
  final bool isGplBuild;
  final String? videoEncoder;
}

class _Plan<T> {
  const _Plan({
    required this.arguments,
    required this.totalMs,
    required this.result,
  });

  final List<String> arguments;
  final int totalMs;
  final T result;
}
