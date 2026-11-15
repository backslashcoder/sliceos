import 'dart:convert';

import '../errors.dart';
import '../models/media_info.dart';

/// Arguments that make ffprobe print the JSON [parseFfprobeJson] understands.
List<String> ffprobeArguments(String sourcePath) => [
  '-v',
  'error',
  '-print_format',
  'json',
  '-show_format',
  '-show_streams',
  sourcePath,
];

/// Converts `ffprobe -print_format json -show_format -show_streams` output.
MediaInfo parseFfprobeJson(String json, {required String path}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    throw InvalidMediaException('Could not read media metadata', details: '$e');
  }
  if (decoded is! Map<String, Object?>) {
    throw const InvalidMediaException('Unexpected media metadata format');
  }
  final format = decoded['format'];
  if (format is! Map<String, Object?>) {
    throw const InvalidMediaException(
      'File is not a recognised media container',
    );
  }

  final video = <VideoStreamInfo>[];
  final audio = <AudioStreamInfo>[];
  for (final raw in (decoded['streams'] as List<Object?>? ?? const [])) {
    final stream = raw as Map<String, Object?>;
    final tags = (stream['tags'] as Map<String, Object?>?) ?? const {};
    switch (stream['codec_type']) {
      case 'video':
        // Cover art is exposed as a video stream; it is not footage.
        final disposition = stream['disposition'] as Map<String, Object?>?;
        if (disposition?['attached_pic'] == 1) continue;
        final avg = _parseRate(stream['avg_frame_rate']);
        final base = _parseRate(stream['r_frame_rate']);
        video.add(
          VideoStreamInfo(
            index: stream['index'] as int,
            codec: stream['codec_name'] as String? ?? 'unknown',
            width: stream['width'] as int? ?? 0,
            height: stream['height'] as int? ?? 0,
            rotationDegrees: _rotation(stream, tags),
            frameRate: avg > 0 ? avg : base,
            isVariableFrameRate:
                avg > 0 && base > 0 && (avg - base).abs() / base > 0.01,
            pixelFormat: stream['pix_fmt'] as String?,
            bitRate: _parseInt(stream['bit_rate']),
          ),
        );
      case 'audio':
        audio.add(
          AudioStreamInfo(
            index: stream['index'] as int,
            codec: stream['codec_name'] as String? ?? 'unknown',
            channels: stream['channels'] as int? ?? 0,
            sampleRate: _parseInt(stream['sample_rate']) ?? 0,
            language: tags['language'] as String?,
            title: tags['title'] as String?,
            bitRate: _parseInt(stream['bit_rate']),
          ),
        );
    }
  }

  final seconds = double.tryParse('${format['duration']}') ?? 0;
  return MediaInfo(
    path: path,
    formatName: format['format_name'] as String? ?? 'unknown',
    durationMs: (seconds * 1000).round(),
    sizeBytes: _parseInt(format['size']) ?? 0,
    bitRate: _parseInt(format['bit_rate']),
    videoStreams: video,
    audioStreams: audio,
  );
}

int? _parseInt(Object? value) => value == null ? null : int.tryParse('$value');

/// Parses ffprobe's `num/den` rational, returning 0 for `0/0` or garbage.
double _parseRate(Object? value) {
  final parts = '$value'.split('/');
  final num = double.tryParse(parts[0]) ?? 0;
  final den = parts.length > 1 ? (double.tryParse(parts[1]) ?? 0) : 1.0;
  return den == 0 ? 0 : num / den;
}

/// Clockwise display rotation, normalised to 0/90/180/270.
///
/// Current FFmpeg reports a display-matrix side data entry whose `rotation`
/// is counter-clockwise; older builds expose a clockwise `rotate` tag.
int _rotation(Map<String, Object?> stream, Map<String, Object?> tags) {
  num? clockwise;
  for (final raw in (stream['side_data_list'] as List<Object?>? ?? const [])) {
    final rotation = (raw as Map<String, Object?>)['rotation'];
    if (rotation is num) clockwise = -rotation;
  }
  clockwise ??= num.tryParse('${tags['rotate']}');
  if (clockwise == null) return 0;
  final normalised = ((clockwise.round() % 360) + 360) % 360;
  return (normalised / 90).round() % 4 * 90;
}
