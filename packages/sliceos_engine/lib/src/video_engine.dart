import 'models/clip_candidate.dart';
import 'models/media_info.dart';
import 'models/processing_job.dart';
import 'models/requests.dart';
import 'models/transcript.dart';

/// Contract every platform media engine implements.
///
/// Long-running operations return an [EngineJob] immediately; progress arrives
/// on its stream and the outcome on its future. Operations a platform cannot
/// perform yet throw `EngineUnsupportedException`; check [capabilities] first.
abstract interface class VideoEngine {
  /// Reports what this engine can do on the current device.
  Future<EngineCapabilities> capabilities();

  /// Reads container and stream metadata without decoding the media.
  Future<MediaInfo> inspect(String sourcePath);

  /// Extracts audio as 16 kHz mono WAV. Completes with the output path.
  EngineJob<String> extractAudio(AudioExtractionRequest request);

  /// Writes one JPEG frame. Completes with the output path.
  EngineJob<String> generateThumbnail(ThumbnailRequest request);

  /// Transcribes extracted audio with a local Whisper model.
  EngineJob<Transcript> transcribe(TranscriptionRequest request);

  /// Proposes highlight candidates from a transcript, fully offline.
  Future<List<ClipCandidate>> detectHighlights(HighlightRequest request);

  /// Renders one clip to a local MP4.
  EngineJob<RenderResult> renderClip(RenderRequest request);

  /// Requests cancellation. Partial output is removed. No-op for unknown or
  /// already finished jobs.
  Future<void> cancel(String jobId);

  /// Latest snapshot of a job started by this engine instance.
  ProcessingJob? jobStatus(String jobId);

  /// Emits a snapshot every time any job changes state or progress.
  Stream<ProcessingJob> get jobUpdates;

  /// Cancels running jobs and releases native resources.
  Future<void> dispose();
}
