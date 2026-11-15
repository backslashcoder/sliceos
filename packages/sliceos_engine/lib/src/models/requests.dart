import 'clip.dart';
import 'media_info.dart';
import 'transcript.dart';

/// Extracts one audio track as 16 kHz mono 16-bit PCM WAV, the input format
/// whisper.cpp expects.
class AudioExtractionRequest {
  const AudioExtractionRequest({
    required this.sourcePath,
    required this.outputPath,
    this.audioTrack = 0,
    this.startMs,
    this.endMs,
  });

  final String sourcePath;
  final String outputPath;

  /// Ordinal among the audio streams (0 is the first audio track).
  final int audioTrack;
  final int? startMs;
  final int? endMs;
}

/// Writes a single JPEG frame.
class ThumbnailRequest {
  const ThumbnailRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.positionMs,
    this.width = 480,
  });

  final String sourcePath;
  final String outputPath;
  final int positionMs;

  /// Output width in pixels; height follows the display aspect ratio.
  final int width;
}

class TranscriptionRequest {
  const TranscriptionRequest({
    required this.audioPath,
    required this.modelPath,
    this.language,
  });

  /// 16 kHz mono WAV produced by audio extraction.
  final String audioPath;

  /// Local whisper.cpp model file.
  final String modelPath;

  /// ISO 639-1 code, or null to auto-detect.
  final String? language;
}

class HighlightRequest {
  const HighlightRequest({
    required this.segments,
    required this.mediaDurationMs,
    this.maxCandidates = 10,
    this.minDurationMs = 15000,
    this.maxDurationMs = 90000,
  });

  final List<TranscriptSegment> segments;
  final int mediaDurationMs;
  final int maxCandidates;
  final int minDurationMs;
  final int maxDurationMs;
}

/// Renders one clip to a local MP4 (H.264 video, AAC audio).
class RenderRequest {
  const RenderRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.startMs,
    required this.endMs,
    this.aspectRatio = ClipAspectRatio.vertical9x16,
    this.crop = CropConfig.centered,
    this.targetShortSide = 1080,
    this.audioTrack = 0,
    this.mediaInfo,
  });

  final String sourcePath;
  final String outputPath;
  final int startMs;
  final int endMs;
  final ClipAspectRatio aspectRatio;
  final CropConfig crop;

  /// Length of the output's shorter side in pixels (720, 1080, 2160). The
  /// engine never upscales beyond the cropped source region.
  final int targetShortSide;

  /// Ordinal among the audio streams (0 is the first audio track).
  final int audioTrack;

  /// Previously inspected metadata. When null the engine inspects the source.
  final MediaInfo? mediaInfo;

  int get durationMs => endMs - startMs;
}

/// Result of a completed render.
class RenderResult {
  const RenderResult({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.videoEncoder,
  });

  final String outputPath;
  final int width;
  final int height;
  final int durationMs;

  /// FFmpeg encoder name used for the video stream.
  final String videoEncoder;
}

/// Progress of a running job.
class RenderProgress {
  const RenderProgress({
    required this.processedMs,
    required this.totalMs,
    this.speed,
  });

  /// Media time already processed.
  final int processedMs;

  /// Media time the job will process in total (0 when unknown).
  final int totalMs;

  /// Processing speed relative to realtime, when reported.
  final double? speed;

  /// 0..1, or null when the total is unknown.
  double? get fraction =>
      totalMs <= 0 ? null : (processedMs / totalMs).clamp(0.0, 1.0).toDouble();
}

/// What a platform engine can currently do. The UI uses this to show honest
/// availability instead of offering operations that would fail.
class EngineCapabilities {
  const EngineCapabilities({
    required this.platform,
    required this.canInspect,
    required this.canExtractAudio,
    required this.canRender,
    required this.canTranscribe,
    required this.canDetectHighlights,
    this.ffmpegVersion,
    this.videoEncoder,
    this.isGplBuild,
    this.unavailableReason,
  });

  final String platform;
  final bool canInspect;
  final bool canExtractAudio;
  final bool canRender;
  final bool canTranscribe;
  final bool canDetectHighlights;
  final String? ffmpegVersion;

  /// H.264 encoder the engine will use for rendering.
  final String? videoEncoder;

  /// True when the FFmpeg build was configured with `--enable-gpl`. Matters
  /// for distribution: a GPL build cannot ship inside a closed-source app.
  final bool? isGplBuild;

  /// Why the engine cannot run at all, when that is the case.
  final String? unavailableReason;
}
