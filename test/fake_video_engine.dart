import 'dart:async';

import 'package:sliceos_engine/sliceos_engine.dart';

/// Scriptable [VideoEngine] for Cubit and widget tests.
class FakeVideoEngine implements VideoEngine {
  FakeVideoEngine({this.canRun = true});

  final bool canRun;
  MediaInfo? inspectResult;
  EngineException? inspectError;

  /// Set before calling renderClip; tests drive the job through it.
  final renderProgress = StreamController<RenderProgress>.broadcast();
  final renderResult = Completer<RenderResult>();
  final cancelled = <String>[];

  @override
  Future<EngineCapabilities> capabilities() async => EngineCapabilities(
    platform: 'test',
    canInspect: canRun,
    canExtractAudio: canRun,
    canRender: canRun,
    canTranscribe: false,
    canDetectHighlights: false,
    ffmpegVersion: canRun ? '8.0' : null,
    videoEncoder: canRun ? 'libx264' : null,
    unavailableReason: canRun ? null : 'Engine missing',
  );

  @override
  Future<MediaInfo> inspect(String sourcePath) async {
    if (inspectError case final error?) throw error;
    return inspectResult!;
  }

  @override
  EngineJob<RenderResult> renderClip(RenderRequest request) => EngineJob(
    id: 'job-1',
    progress: renderProgress.stream,
    result: renderResult.future,
  );

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    if (!renderResult.isCompleted) {
      renderResult.completeError(JobCancelledException(jobId));
    }
  }

  @override
  EngineJob<String> extractAudio(AudioExtractionRequest request) =>
      throw UnimplementedError();

  @override
  EngineJob<String> generateThumbnail(ThumbnailRequest request) =>
      throw UnimplementedError();

  @override
  EngineJob<Transcript> transcribe(TranscriptionRequest request) =>
      throw UnimplementedError();

  @override
  Future<List<ClipCandidate>> detectHighlights(
    HighlightRequest request,
  ) async => const HeuristicHighlightDetector().detect(request);

  @override
  ProcessingJob? jobStatus(String jobId) => null;

  @override
  Stream<ProcessingJob> get jobUpdates => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

const sampleMedia = MediaInfo(
  path: r'C:\videos\podcast episode.mp4',
  formatName: 'mov,mp4',
  durationMs: 3725000,
  sizeBytes: 1500000000,
  videoStreams: [
    VideoStreamInfo(
      index: 0,
      codec: 'h264',
      width: 1920,
      height: 1080,
      rotationDegrees: 0,
      frameRate: 30,
      isVariableFrameRate: false,
    ),
  ],
  audioStreams: [
    AudioStreamInfo(index: 1, codec: 'aac', channels: 2, sampleRate: 48000),
  ],
);
