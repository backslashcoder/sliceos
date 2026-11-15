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
