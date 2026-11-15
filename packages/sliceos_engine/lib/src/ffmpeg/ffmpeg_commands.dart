import 'dart:math' as math;

import '../errors.dart';
import '../models/clip.dart';
import '../models/media_info.dart';
import '../models/requests.dart';

/// H.264 encoders the engine knows how to drive, in order of preference.
///
/// `libx264` only exists in GPL builds. `libopenh264` and `h264_mf` (Windows
/// Media Foundation) are available in LGPL builds.
const supportedH264Encoders = ['libx264', 'libopenh264', 'h264_mf'];

/// Options placed before every job's own arguments.
const _commonOptions = ['-hide_banner', '-nostats', '-loglevel', 'error', '-y'];

/// Machine-readable progress on stdout.
const _progressOptions = ['-progress', 'pipe:1'];

String _seconds(int ms) => (ms / 1000).toStringAsFixed(3);

int _even(num value) => math.max(2, (value.floor() ~/ 2) * 2);

/// Pixel rectangle inside the display-oriented source frame.
class CropRect {
  const CropRect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  String toString() => 'CropRect($x, $y, $width, $height)';
}

/// Resolves a normalised [CropConfig] to pixels for a source frame.
CropRect computeCrop({
  required int sourceWidth,
  required int sourceHeight,
  required ClipAspectRatio aspectRatio,
  CropConfig crop = CropConfig.centered,
}) {
  final ratio = aspectRatio.ratio;
  final maxWidth = math.min(sourceWidth.toDouble(), sourceHeight * ratio);
  final width = math.min(_even(maxWidth / crop.zoom), sourceWidth);
  final height = math.min(_even(maxWidth / ratio / crop.zoom), sourceHeight);
  final x = (crop.centerX * sourceWidth - width / 2).round();
  final y = (crop.centerY * sourceHeight - height / 2).round();
  return CropRect(
    x.clamp(0, sourceWidth - width),
    y.clamp(0, sourceHeight - height),
    width,
    height,
  );
}

/// Everything needed to run and describe one render.
class RenderPlan {
  const RenderPlan({
    required this.arguments,
    required this.crop,
    required this.outputWidth,
    required this.outputHeight,
    required this.durationMs,
    required this.videoEncoder,
  });

  final List<String> arguments;
  final CropRect crop;
  final int outputWidth;
  final int outputHeight;
  final int durationMs;
  final String videoEncoder;
}

/// Builds the FFmpeg invocation for [request]. Pure; performs no I/O.
///
/// FFmpeg applies rotation metadata before filters run, so crop geometry is
/// computed against the display dimensions.
RenderPlan planRender(
  RenderRequest request,
  MediaInfo media, {
  required String videoEncoder,
  required String outputPath,
}) {
  final video = media.primaryVideo;
  if (video == null) {
    throw const InvalidRequestException('Source has no video stream');
  }
  if (request.startMs < 0 || request.endMs <= request.startMs) {
    throw const InvalidRequestException('Clip range is empty or negative');
  }
  // Container durations are approximate; allow a small overshoot.
  if (request.startMs >= media.durationMs ||
      request.endMs > media.durationMs + 500) {
    throw InvalidRequestException(
      'Clip range ${request.startMs}-${request.endMs} ms is outside the '
      'media duration of ${media.durationMs} ms',
    );
  }
  if (request.targetShortSide < 2) {
    throw const InvalidRequestException('Target size is too small');
  }
  if (media.hasAudio && request.audioTrack >= media.audioStreams.length) {
    throw InvalidRequestException(
      'Audio track ${request.audioTrack} does not exist '
      '(source has ${media.audioStreams.length})',
    );
  }

  final crop = computeCrop(
    sourceWidth: video.displayWidth,
    sourceHeight: video.displayHeight,
    aspectRatio: request.aspectRatio,
    crop: request.crop,
  );
  final ratio = request.aspectRatio.ratio;
  final int width;
  final int height;
  if (ratio <= 1) {
    width = _even(math.min(request.targetShortSide, crop.width));
    height = _even(width / ratio);
  } else {
    height = _even(math.min(request.targetShortSide, crop.height));
    width = _even(height * ratio);
  }
  final durationMs =
      math.min(request.endMs, media.durationMs) - request.startMs;

  final filter =
      'crop=${crop.width}:${crop.height}:${crop.x}:${crop.y},'
      'scale=$width:$height,setsar=1';

  return RenderPlan(
    crop: crop,
    outputWidth: width,
    outputHeight: height,
    durationMs: durationMs,
    videoEncoder: videoEncoder,
    arguments: [
      ..._commonOptions,
      // Seeking before -i is fast and, because we re-encode, frame accurate.
      '-ss', _seconds(request.startMs),
      '-i', request.sourcePath,
      '-t', _seconds(durationMs),
      '-map', '0:v:0',
      if (media.hasAudio) ...['-map', '0:a:${request.audioTrack}'],
      '-vf', filter,
      ..._videoEncoderOptions(videoEncoder, width, height),
      if (media.hasAudio) ...['-c:a', 'aac', '-b:a', '160k'],
      '-movflags', '+faststart',
      ..._progressOptions,
      '-f', 'mp4',
      outputPath,
    ],
  );
}

List<String> _videoEncoderOptions(String encoder, int width, int height) {
  // Bitrate target for encoders without a constant-quality mode:
  // about 8 Mbit/s at 1080x1920.
  final bitRate = math.max(1000000, width * height * 4);
  return switch (encoder) {
    'libx264' => [
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-pix_fmt',
      'yuv420p',
    ],
    'libopenh264' ||
    'h264_mf' => ['-c:v', encoder, '-b:v', '$bitRate', '-pix_fmt', 'yuv420p'],
    _ => throw InvalidRequestException('Unsupported video encoder: $encoder'),
  };
}

/// 16 kHz mono 16-bit PCM WAV, the input format whisper.cpp expects.
List<String> audioExtractionArguments(
  AudioExtractionRequest request,
  MediaInfo media, {
  required String outputPath,
}) {
  if (request.audioTrack < 0 ||
      request.audioTrack >= media.audioStreams.length) {
    throw InvalidRequestException(
      media.hasAudio
          ? 'Audio track ${request.audioTrack} does not exist '
                '(source has ${media.audioStreams.length})'
          : 'Source has no audio stream',
    );
  }
  final start = request.startMs;
  final end = request.endMs;
  if ((start != null && start < 0) || (end != null && end <= (start ?? 0))) {
    throw const InvalidRequestException('Audio range is empty or negative');
  }
  return [
    ..._commonOptions,
    if (start != null) ...['-ss', _seconds(start)],
    '-i',
    request.sourcePath,
    if (end != null) ...['-t', _seconds(end - (start ?? 0))],
    '-vn',
    '-map',
    '0:a:${request.audioTrack}',
    '-ac',
    '1',
    '-ar',
    '16000',
    '-c:a',
    'pcm_s16le',
    ..._progressOptions,
    '-f',
    'wav',
    outputPath,
  ];
}

/// Media time an audio extraction will process, for progress reporting.
int audioExtractionDurationMs(
  AudioExtractionRequest request,
  MediaInfo media,
) => (request.endMs ?? media.durationMs) - (request.startMs ?? 0);

/// One JPEG frame at the requested position.
List<String> thumbnailArguments(
  ThumbnailRequest request, {
  required String outputPath,
}) {
  if (request.positionMs < 0 || request.width < 2) {
    throw const InvalidRequestException('Invalid thumbnail position or width');
  }
  return [
    ..._commonOptions,
    '-ss',
    _seconds(request.positionMs),
    '-i',
    request.sourcePath,
    '-map',
    '0:v:0',
    '-frames:v',
    '1',
    '-vf',
    'scale=${_even(request.width)}:-2',
    '-c:v',
    'mjpeg',
    '-q:v',
    '3',
    '-f',
    'image2',
    '-update',
    '1',
    outputPath,
  ];
}
