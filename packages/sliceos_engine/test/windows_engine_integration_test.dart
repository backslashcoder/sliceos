// Runs the desktop engine against real FFmpeg binaries and real files.
//
// Binaries are looked up in SLICEOS_FFMPEG_DIR, then the repository's
// native/windows/ffmpeg/bin, then PATH. The whole suite is skipped (and says
// so) when FFmpeg is not available.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:test/test.dart';

FfmpegBinaries? findBinaries() {
  final binaries = FfmpegBinaries.locate(
    directory: p.join('..', '..', 'native', 'windows', 'ffmpeg', 'bin'),
  );
  try {
    final ok =
        Process.runSync(binaries.ffmpeg, ['-version']).exitCode == 0 &&
        Process.runSync(binaries.ffprobe, ['-version']).exitCode == 0;
    return ok ? binaries : null;
  } on ProcessException {
    return null;
  }
}

void main() {
  final binaries = findBinaries();
  if (binaries == null) {
    test('desktop engine integration', () {}, skip: 'FFmpeg/FFprobe not found');
    return;
  }

  late Directory temp;
  late WindowsVideoEngine engine;
  late String source; // 6 s, 1280x720, two audio tracks, awkward file name.
  late String rotated; // Same footage flagged as rotated 90 degrees.
  late String longSource; // 60 s, used for cancellation.

  void ffmpeg(List<String> args) {
    final result = Process.runSync(binaries.ffmpeg, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      ...args,
    ]);
    if (result.exitCode != 0) {
      fail('fixture generation failed: ${result.stderr}');
    }
  }

  setUpAll(() {
    // A directory name with a space and non-ASCII characters on purpose.
    temp = Directory.systemTemp.createTempSync('sliceos engine tëst 视频 ');
    source = p.join(temp.path, 'my clip ünï 日本語.mp4');
    rotated = p.join(temp.path, 'rotated.mp4');
    longSource = p.join(temp.path, 'long.mp4');
    ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=1280x720:rate=30',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=48000',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=880:sample_rate=44100',
      '-t',
      '6',
      '-map',
      '0:v',
      '-map',
      '1:a',
      '-map',
      '2:a',
      '-c:v',
      'mpeg4',
      '-q:v',
      '5',
      '-c:a',
      'aac',
      '-metadata:s:a:0',
      'language=eng',
      '-metadata:s:a:1',
      'language=hin',
      source,
    ]);
    ffmpeg([
      '-display_rotation',
      '90',
      '-i',
      source,
      '-map',
      '0',
      '-c',
      'copy',
      rotated,
    ]);
    ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=1920x1080:rate=30',
      '-t',
      '60',
      '-c:v',
      'mpeg4',
      '-q:v',
      '8',
      longSource,
    ]);
    engine = WindowsVideoEngine(binaries: binaries);
  });

  tearDownAll(() async {
    await engine.dispose();
    temp.deleteSync(recursive: true);
  });

  List<String> partFiles() => [
    for (final f in temp.listSync())
      if (f.path.endsWith('.part')) f.path,
  ];

  test('reports toolchain capabilities', () async {
    final caps = await engine.capabilities();
    expect(caps.canInspect, isTrue);
    expect(caps.canRender, isTrue, reason: caps.unavailableReason);
    expect(caps.ffmpegVersion, isNotNull);
    printOnFailure(
      '${caps.ffmpegVersion} ${caps.videoEncoder} gpl=${caps.isGplBuild}',
    );
  });

  test('inspects a file with spaces and Unicode in its path', () async {
    final info = await engine.inspect(source);
    expect(info.durationMs, closeTo(6000, 150));
    expect(info.sizeBytes, File(source).lengthSync());
    final video = info.primaryVideo!;
    expect((video.width, video.height, video.rotationDegrees), (1280, 720, 0));
    expect(video.frameRate, closeTo(30, 0.1));
    expect(info.audioStreams.map((a) => a.language), ['eng', 'hin']);
    expect(info.audioStreams.map((a) => a.sampleRate), [48000, 44100]);
  });

  test('reads rotation metadata', () async {
    final video = (await engine.inspect(rotated)).primaryVideo!;
    expect(video.rotationDegrees, anyOf(90, 270));
    expect((video.displayWidth, video.displayHeight), (720, 1280));
  });

  test('rejects missing files and non-media files', () async {
    expect(
      engine.inspect(p.join(temp.path, 'nope.mp4')),
      throwsA(isA<MediaNotFoundException>()),
    );
    final text = File(p.join(temp.path, 'notes.txt'))
      ..writeAsStringSync('hello');
    expect(engine.inspect(text.path), throwsA(isA<InvalidMediaException>()));
  });

  test('extracts the selected audio track as 16 kHz mono WAV', () async {
    final output = p.join(temp.path, 'audio out', 'track 2.wav');
    final job = engine.extractAudio(
      AudioExtractionRequest(
        sourcePath: source,
        outputPath: output,
        audioTrack: 1,
      ),
    );
    expect(await job.result, output);
    final info = await engine.inspect(output);
    final audio = info.audioStreams.single;
    expect(
      (audio.codec, audio.sampleRate, audio.channels),
      ('pcm_s16le', 16000, 1),
    );
    expect(info.durationMs, closeTo(6000, 150));
    expect(engine.jobStatus(job.id)!.status, JobStatus.completed);
  });

  test('writes a thumbnail', () async {
    final output = p.join(temp.path, 'thumb.jpg');
    await engine
        .generateThumbnail(
          ThumbnailRequest(
            sourcePath: source,
            outputPath: output,
            positionMs: 3000,
            width: 320,
          ),
        )
        .result;
    final video = (await engine.inspect(output)).primaryVideo!;
    expect((video.width, video.height), (320, 180));
  });

  test('renders a vertical clip with progress', () async {
    final output = p.join(temp.path, 'clip 9x16 ✓.mp4');
    final job = engine.renderClip(
      RenderRequest(
        sourcePath: source,
        outputPath: output,
        startMs: 2000,
        endMs: 5000,
      ),
    );
    final progress = <RenderProgress>[];
    job.progress.listen(progress.add);
    final result = await job.result;

    expect((result.width, result.height), (404, 718));
    expect(progress, isNotEmpty);
    expect(progress.last.fraction, 1.0);

    final info = await engine.inspect(output);
    final video = info.primaryVideo!;
    expect(video.codec, 'h264');
    expect((video.width, video.height), (404, 718));
    expect(info.durationMs, closeTo(3000, 200));
    expect(info.audioStreams.single.codec, 'aac');
    expect(partFiles(), isEmpty);
  });

  test('renders rotated footage upright as a square', () async {
    final output = p.join(temp.path, 'square.mp4');
    final result = await engine
        .renderClip(
          RenderRequest(
            sourcePath: rotated,
            outputPath: output,
            startMs: 0,
            endMs: 2000,
            aspectRatio: ClipAspectRatio.square1x1,
            targetShortSide: 480,
          ),
        )
        .result;
    expect((result.width, result.height), (480, 480));
    final video = (await engine.inspect(output)).primaryVideo!;
    expect((video.displayWidth, video.displayHeight), (480, 480));
  });

  test('cancelling a render removes partial output', () async {
    final output = p.join(temp.path, 'cancelled.mp4');
    final job = engine.renderClip(
      RenderRequest(
        sourcePath: longSource,
        outputPath: output,
        startMs: 0,
        endMs: 60000,
        aspectRatio: ClipAspectRatio.landscape16x9,
      ),
    );
    final outcome = expectLater(
      job.result,
      throwsA(isA<JobCancelledException>()),
    );
    await engine.jobUpdates.firstWhere(
      (j) => j.id == job.id && j.status == JobStatus.running,
    );
    await engine.cancel(job.id);
    await outcome;

    expect(engine.jobStatus(job.id)!.status, JobStatus.cancelled);
    expect(File(output).existsSync(), isFalse);
    expect(partFiles(), isEmpty);
  });

  test('a failed job reports the error and leaves no output', () async {
    final output = p.join(temp.path, 'missing-out.mp4');
    final job = engine.renderClip(
      RenderRequest(
        sourcePath: p.join(temp.path, 'gone.mp4'),
        outputPath: output,
        startMs: 0,
        endMs: 1000,
      ),
    );
    await expectLater(job.result, throwsA(isA<MediaNotFoundException>()));
    expect(engine.jobStatus(job.id)!.status, JobStatus.failed);
    expect(File(output).existsSync(), isFalse);

    final outOfRange = engine.renderClip(
      RenderRequest(
        sourcePath: source,
        outputPath: output,
        startMs: 10000,
        endMs: 20000,
      ),
    );
    await expectLater(
      outOfRange.result,
      throwsA(isA<InvalidRequestException>()),
    );
    expect(partFiles(), isEmpty);
  });
}
