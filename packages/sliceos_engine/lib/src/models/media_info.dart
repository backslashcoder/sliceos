/// Metadata of a local media file, as reported by the platform probe.
class MediaInfo {
  const MediaInfo({
    required this.path,
    required this.formatName,
    required this.durationMs,
    required this.sizeBytes,
    required this.videoStreams,
    required this.audioStreams,
    this.bitRate,
  });

  final String path;
  final String formatName;
  final int durationMs;
  final int sizeBytes;
  final int? bitRate;
  final List<VideoStreamInfo> videoStreams;
  final List<AudioStreamInfo> audioStreams;

  VideoStreamInfo? get primaryVideo =>
      videoStreams.isEmpty ? null : videoStreams.first;

  bool get hasVideo => videoStreams.isNotEmpty;
  bool get hasAudio => audioStreams.isNotEmpty;

  Map<String, Object?> toJson() => {
    'path': path,
    'formatName': formatName,
    'durationMs': durationMs,
    'sizeBytes': sizeBytes,
    'bitRate': bitRate,
    'videoStreams': [for (final s in videoStreams) s.toJson()],
    'audioStreams': [for (final s in audioStreams) s.toJson()],
  };

  factory MediaInfo.fromJson(Map<String, Object?> json) => MediaInfo(
    path: json['path'] as String,
    formatName: json['formatName'] as String,
    durationMs: json['durationMs'] as int,
    sizeBytes: json['sizeBytes'] as int,
    bitRate: json['bitRate'] as int?,
    videoStreams: [
      for (final s in json['videoStreams'] as List<Object?>)
        VideoStreamInfo.fromJson(s as Map<String, Object?>),
    ],
    audioStreams: [
      for (final s in json['audioStreams'] as List<Object?>)
        AudioStreamInfo.fromJson(s as Map<String, Object?>),
    ],
  );
}

class VideoStreamInfo {
  const VideoStreamInfo({
    required this.index,
    required this.codec,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.frameRate,
    required this.isVariableFrameRate,
    this.pixelFormat,
    this.bitRate,
  });

  /// Stream index inside the container.
  final int index;
  final String codec;

  /// Coded (stored) dimensions, before rotation metadata is applied.
  final int width;
  final int height;

  /// Clockwise rotation a player applies for display: 0, 90, 180 or 270.
  final int rotationDegrees;

  /// Average frames per second (0 when unknown).
  final double frameRate;

  /// True when the average and base frame rates disagree, which indicates a
  /// variable-frame-rate recording (typical for phone and screen captures).
  final bool isVariableFrameRate;
  final String? pixelFormat;
  final int? bitRate;

  bool get _isSideways => rotationDegrees == 90 || rotationDegrees == 270;

  /// Dimensions as displayed, after rotation metadata is applied. Crop
  /// geometry is always expressed against these.
  int get displayWidth => _isSideways ? height : width;
  int get displayHeight => _isSideways ? width : height;

  Map<String, Object?> toJson() => {
    'index': index,
    'codec': codec,
    'width': width,
    'height': height,
    'rotationDegrees': rotationDegrees,
    'frameRate': frameRate,
    'isVariableFrameRate': isVariableFrameRate,
    'pixelFormat': pixelFormat,
    'bitRate': bitRate,
  };

  factory VideoStreamInfo.fromJson(Map<String, Object?> json) =>
      VideoStreamInfo(
        index: json['index'] as int,
        codec: json['codec'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
        rotationDegrees: json['rotationDegrees'] as int,
        frameRate: (json['frameRate'] as num).toDouble(),
        isVariableFrameRate: json['isVariableFrameRate'] as bool,
        pixelFormat: json['pixelFormat'] as String?,
        bitRate: json['bitRate'] as int?,
      );
}

class AudioStreamInfo {
  const AudioStreamInfo({
    required this.index,
    required this.codec,
    required this.channels,
    required this.sampleRate,
    this.language,
    this.title,
    this.bitRate,
  });

  /// Stream index inside the container.
  final int index;
  final String codec;
  final int channels;
  final int sampleRate;
  final String? language;
  final String? title;
  final int? bitRate;

  Map<String, Object?> toJson() => {
    'index': index,
    'codec': codec,
    'channels': channels,
    'sampleRate': sampleRate,
    'language': language,
    'title': title,
    'bitRate': bitRate,
  };

  factory AudioStreamInfo.fromJson(Map<String, Object?> json) =>
      AudioStreamInfo(
        index: json['index'] as int,
        codec: json['codec'] as String,
        channels: json['channels'] as int,
        sampleRate: json['sampleRate'] as int,
        language: json['language'] as String?,
        title: json['title'] as String?,
        bitRate: json['bitRate'] as int?,
      );
}
