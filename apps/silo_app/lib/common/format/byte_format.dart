/// Human-readable byte count, e.g. `4.37 GiB`.
String formatBytes({required int bytes}) {
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : 2;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Transfer rate, e.g. `12.40 MiB/s`.
String formatRate({required double bytesPerSecond}) {
  if (bytesPerSecond <= 0) return '—';
  return '${formatBytes(bytes: bytesPerSecond.round())}/s';
}

/// Compact duration, e.g. `2m03s`.
String formatDuration({required Duration? duration}) {
  final value = duration;
  if (value == null) return '—';
  if (value.inHours > 0) {
    final minutes = (value.inMinutes % 60).toString().padLeft(2, '0');
    return '${value.inHours}h${minutes}m';
  }
  if (value.inMinutes > 0) {
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '${value.inMinutes}m${seconds}s';
  }
  return '${value.inSeconds}s';
}
