import '../models/requests.dart';

/// Parses the `key=value` blocks FFmpeg writes with `-progress pipe:1`.
///
/// Feed it one line at a time; it returns a [RenderProgress] each time a block
/// ends (the `progress=continue` / `progress=end` line), otherwise null.
class FfmpegProgressParser {
  FfmpegProgressParser({required this.totalMs});

  final int totalMs;
  int _processedMs = 0;
  double? _speed;

  RenderProgress? addLine(String line) {
    final separator = line.indexOf('=');
    if (separator <= 0) return null;
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    switch (key) {
      case 'out_time_us':
        // "N/A" until the first frame is written.
        final micros = int.tryParse(value);
        if (micros != null && micros >= 0) _processedMs = micros ~/ 1000;
      case 'speed':
        _speed = double.tryParse(value.replaceAll('x', ''));
      case 'progress':
        return RenderProgress(
          processedMs: value == 'end' && totalMs > 0 ? totalMs : _processedMs,
          totalMs: totalMs,
          speed: _speed,
        );
    }
    return null;
  }
}
