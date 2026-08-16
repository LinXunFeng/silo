/// Why a download stopped.
enum DownloadOutcome {
  /// Every byte arrived and, when a digest was known, it matched.
  completed,

  /// [DownloadHandle.pause] was called; the `.part.json` sidecar is intact and
  /// the same call will resume where it left off.
  paused,

  /// [DownloadHandle.cancel] was called; partial data is discarded.
  cancelled,
}

/// A point-in-time snapshot of a running download.
class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.bytesPerSecond,
    required this.activeConnections,
    required this.completedChunks,
    required this.totalChunks,
    this.carriedOver = 0,
  });

  /// Bytes on disk so far, including bytes carried over from a previous run.
  final int received;

  /// Bytes that were already on disk when this run started, from an earlier
  /// interrupted attempt. Reporting these as "downloaded" would overstate what
  /// actually crossed the network.
  final int carriedOver;

  /// Bytes this run actually pulled over the network.
  int get transferred => received - carriedOver;

  /// Total size in bytes, or null when the server would not say.
  final int? total;

  /// Rolling transfer rate.
  final double bytesPerSecond;

  final int activeConnections;
  final int completedChunks;
  final int totalChunks;

  /// 0.0–1.0, or null when [total] is unknown.
  double? get fraction {
    final int? t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0);
  }

  /// Estimated time remaining, or null when it cannot be estimated.
  Duration? get eta {
    final int? t = total;
    if (t == null || bytesPerSecond <= 0 || received >= t) return null;
    return Duration(seconds: ((t - received) / bytesPerSecond).round());
  }

  @override
  String toString() =>
      'DownloadProgress($received/${total ?? '?'}, '
      '${(bytesPerSecond / (1 << 20)).toStringAsFixed(2)} MiB/s, '
      '$completedChunks/$totalChunks chunks)';
}

/// Base class for download failures that callers may want to distinguish.
class DownloadException implements Exception {
  DownloadException(this.message, {this.uri, this.statusCode});

  final String message;
  final Uri? uri;
  final int? statusCode;

  @override
  String toString() => 'DownloadException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}'
      '${uri != null ? ' [$uri]' : ''}';
}

/// The downloaded bytes did not match the digest the source advertised.
///
/// This is the failure that matters most in practice: a silently truncated or
/// corrupted GGUF does not error, it crashes the model loader much later.
class ChecksumMismatchException extends DownloadException {
  ChecksumMismatchException({
    required this.expected,
    required this.actual,
    required this.path,
  }) : super('checksum mismatch for $path: expected $expected, got $actual');

  final String expected;
  final String actual;
  final String path;
}

/// Raised when a resumed download no longer matches its sidecar.
class StalePartException extends DownloadException {
  StalePartException(super.message);
}
