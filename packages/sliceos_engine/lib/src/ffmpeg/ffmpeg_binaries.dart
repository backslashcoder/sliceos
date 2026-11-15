import 'dart:io';

import 'package:path/path.dart' as p;

/// Locations of the FFmpeg command-line tools used by desktop engines.
class FfmpegBinaries {
  const FfmpegBinaries({required this.ffmpeg, required this.ffprobe});

  /// Environment variable that overrides the lookup directory.
  static const directoryVariable = 'SLICEOS_FFMPEG_DIR';

  final String ffmpeg;
  final String ffprobe;

  static String get _suffix => Platform.isWindows ? '.exe' : '';

  factory FfmpegBinaries.inDirectory(String directory) => FfmpegBinaries(
    ffmpeg: p.join(directory, 'ffmpeg$_suffix'),
    ffprobe: p.join(directory, 'ffprobe$_suffix'),
  );

  bool get existOnDisk =>
      File(ffmpeg).existsSync() && File(ffprobe).existsSync();

  /// Finds the tools, in order: [directory], `SLICEOS_FFMPEG_DIR`, an `ffmpeg`
  /// folder beside the running executable (the bundled location), then bare
  /// command names resolved through `PATH`.
  ///
  /// The `PATH` fallback is not checked here; the engine reports a missing
  /// tool the first time it tries to run it.
  static FfmpegBinaries locate({
    String? directory,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final candidates = [
      ?directory,
      ?env[directoryVariable],
      p.join(p.dirname(Platform.resolvedExecutable), 'ffmpeg'),
    ];
    for (final dir in candidates) {
      final binaries = FfmpegBinaries.inDirectory(dir);
      if (binaries.existOnDisk) return binaries;
    }
    return FfmpegBinaries(ffmpeg: 'ffmpeg$_suffix', ffprobe: 'ffprobe$_suffix');
  }
}
