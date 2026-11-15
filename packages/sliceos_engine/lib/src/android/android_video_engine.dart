import 'dart:async';

import '../errors.dart';
import '../models/clip_candidate.dart';
import '../models/media_info.dart';
import '../models/processing_job.dart';
import '../models/requests.dart';
import '../models/transcript.dart';
import '../video_engine.dart';

/// Android engine.
///
/// Not implemented yet. The native FFmpeg integration (NDK build + JNI bridge)
/// is the next milestone; see docs/TECHNICAL_DECISIONS.md (TD-004). Until it
/// lands, [capabilities] reports everything as unavailable and every
/// operation throws [EngineUnsupportedException] so the app can show an
/// honest "not available on this device yet" state instead of faking output.
class AndroidVideoEngine implements VideoEngine {
  static const _reason =
      'Video processing on Android is not available in this build yet';

  final _updates = StreamController<ProcessingJob>.broadcast();

  @override
  Future<EngineCapabilities> capabilities() async => const EngineCapabilities(
    platform: 'android',
    canInspect: false,
    canExtractAudio: false,
    canRender: false,
    canTranscribe: false,
    canDetectHighlights: false,
    unavailableReason: _reason,
  );

  @override
  Future<MediaInfo> inspect(String sourcePath) async =>
      throw const EngineUnsupportedException(_reason);

  @override
  EngineJob<String> extractAudio(AudioExtractionRequest request) =>
      throw const EngineUnsupportedException(_reason);

  @override
  EngineJob<String> generateThumbnail(ThumbnailRequest request) =>
      throw const EngineUnsupportedException(_reason);

  @override
  EngineJob<Transcript> transcribe(TranscriptionRequest request) =>
      throw const EngineUnsupportedException(_reason);

  @override
  Future<List<ClipCandidate>> detectHighlights(
    HighlightRequest request,
  ) async => throw const EngineUnsupportedException(_reason);

  @override
  EngineJob<RenderResult> renderClip(RenderRequest request) =>
      throw const EngineUnsupportedException(_reason);

  @override
  Future<void> cancel(String jobId) async {}

  @override
  ProcessingJob? jobStatus(String jobId) => null;

  @override
  Stream<ProcessingJob> get jobUpdates => _updates.stream;

  @override
  Future<void> dispose() => _updates.close();
}
