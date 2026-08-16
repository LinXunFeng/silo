import 'dart:async';

/// Token-bucket rate limiter shared by every worker of a download.
///
/// Limiting the aggregate rather than per-connection is the point: mirrors
/// throttle by client, so eight connections each capped at 1 MiB/s is not the
/// same thing as 8 MiB/s across the download.
class RateLimiter {
  RateLimiter({int? bytesPerSecond, this.burst = 1 << 20})
      : _bytesPerSecond = bytesPerSecond {
    _tokens = burst.toDouble();
    _lastRefill = DateTime.now().microsecondsSinceEpoch;
  }

  /// Maximum bytes that may be consumed in a single instant.
  final int burst;

  int? _bytesPerSecond;
  double _tokens = 0;
  int _lastRefill = 0;
  Future<void>? _pending;

  /// Bytes per second, or null for unlimited. Safe to change mid-download.
  int? get bytesPerSecond => _bytesPerSecond;

  set bytesPerSecond(int? value) {
    _refill();
    _bytesPerSecond = (value != null && value <= 0) ? null : value;
  }

  bool get isLimited => _bytesPerSecond != null;

  /// Waits until [bytes] may be transferred.
  ///
  /// Calls are serialised so concurrent workers queue fairly instead of all
  /// draining the same tokens.
  Future<void> consume(int bytes) {
    if (!isLimited || bytes <= 0) return Future<void>.value();
    final Future<void> previous = _pending ?? Future<void>.value();
    final Future<void> next = previous.then((_) => _consume(bytes));
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> _consume(int bytes) async {
    var remaining = bytes;
    while (remaining > 0) {
      _refill();
      final int rate = _bytesPerSecond ?? 0;
      if (rate <= 0) return;
      if (_tokens >= 1) {
        final int take = remaining < _tokens ? remaining : _tokens.floor();
        _tokens -= take;
        remaining -= take;
        if (remaining == 0) return;
      }
      // Wait for enough tokens to cover what is left, capped so that a rate
      // change mid-wait is picked up reasonably promptly.
      final double needed = remaining - _tokens;
      final int waitUs = (needed / rate * 1000000).ceil().clamp(1000, 200000);
      await Future<void>.delayed(Duration(microseconds: waitUs));
    }
  }

  void _refill() {
    final int now = DateTime.now().microsecondsSinceEpoch;
    final int rate = _bytesPerSecond ?? 0;
    if (rate > 0) {
      final double elapsed = (now - _lastRefill) / 1000000;
      _tokens += elapsed * rate;
      final double cap = burst.toDouble();
      if (_tokens > cap) _tokens = cap;
    }
    _lastRefill = now;
  }
}
