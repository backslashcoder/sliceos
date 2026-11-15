/// `1:02:03` or `2:03`.
String formatDuration(int milliseconds) {
  final total = Duration(milliseconds: milliseconds);
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return total.inHours > 0
      ? '${total.inHours}:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}

/// `1.4 GB`, `320 MB`, `12 KB`.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// `1:02:03.5` or `2:03.5` — a position precise to a tenth of a second.
String formatTimestamp(int milliseconds) {
  final tenths = (milliseconds / 100).round();
  final hours = tenths ~/ 36000;
  final minutes = (tenths ~/ 600) % 60;
  final seconds = ((tenths % 600) / 10).toStringAsFixed(1).padLeft(4, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}

/// Parses `ss`, `m:ss`, `h:mm:ss`, each with optional decimals, to
/// milliseconds. Returns null for anything else.
int? parseTimestamp(String input) {
  final parts = input.trim().split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  var seconds = 0.0;
  for (final (index, part) in parts.indexed) {
    final isLast = index == parts.length - 1;
    final value = isLast
        ? double.tryParse(part)
        : int.tryParse(part)?.toDouble();
    if (value == null || value < 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    // Only the leading field may exceed 59.
    if (index > 0 && value >= 60) return null;
    seconds = seconds * 60 + value;
  }
  return (seconds * 1000).round();
}
