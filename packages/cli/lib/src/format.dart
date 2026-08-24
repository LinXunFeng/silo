import 'dart:io';

/// Human-readable byte count, e.g. `4.37 GiB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 2)} ${units[unit]}';
}

String formatRate(double bytesPerSecond) =>
    bytesPerSecond <= 0 ? '--' : '${formatBytes(bytesPerSecond.round())}/s';

String formatDuration(Duration? d) {
  if (d == null) return '--';
  if (d.inHours > 0) {
    return '${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  }
  return '${d.inSeconds}s';
}

/// A fixed-width progress bar, e.g. `[####------]`.
String progressBar(double? fraction, {int width = 24}) {
  if (fraction == null) return '[${'?' * width}]';
  final int filled = (fraction.clamp(0.0, 1.0) * width).round();
  return '[${'#' * filled}${'-' * (width - filled)}]';
}

/// Writes a line that later output overwrites, when attached to a terminal.
///
/// Falls back to plain lines when piped, so logs stay readable.
class StatusLine {
  StatusLine({IOSink? sink}) : _sink = sink ?? stdout;

  final IOSink _sink;
  int _lastLength = 0;
  bool _dirty = false;

  bool get interactive => stdout.hasTerminal;

  void update(String text) {
    if (!interactive) return;
    final String padded = text.padRight(_lastLength);
    _sink.write('\r$padded');
    _lastLength = text.length;
    _dirty = true;
  }

  /// Clears the transient line so ordinary output starts clean.
  void clear() {
    if (!interactive || !_dirty) return;
    _sink.write('\r${' ' * _lastLength}\r');
    _lastLength = 0;
    _dirty = false;
  }

  /// Ends the transient line, keeping [finalText] on screen.
  void finish(String finalText) {
    if (interactive) {
      clear();
    }
    _sink.writeln(finalText);
  }
}
