import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../util/sha256.dart';
import 'download_types.dart';
import 'http_probe.dart';
import 'part_file.dart';
import 'rate_limiter.dart';

/// Tunables for [ChunkedDownloader].
class DownloadOptions {
  const DownloadOptions({
    this.connections = 8,
    this.targetChunkSize = 16 << 20,
    this.maxChunks = 4096,
    this.maxRetriesPerChunk = 5,
    this.timeout = const Duration(seconds: 60),
    this.bytesPerSecond,
    this.headers = const <String, String>{},
    this.progressInterval = const Duration(milliseconds: 250),
    this.sidecarInterval = const Duration(seconds: 1),
    this.verifyChecksum = true,
  });

  /// Parallel connections. Mirrors throttle aggressively above ~16, at which
  /// point more connections make the download slower, not faster.
  final int connections;

  /// Preferred bytes per chunk. Smaller chunks bound how much work a stalled
  /// connection can hold hostage at the tail of a download.
  final int targetChunkSize;

  /// Upper bound on chunk count, so the sidecar stays small on huge files.
  final int maxChunks;

  final int maxRetriesPerChunk;
  final Duration timeout;

  /// Aggregate throttle across all connections, or null for unlimited.
  final int? bytesPerSecond;

  final Map<String, String> headers;
  final Duration progressInterval;
  final Duration sidecarInterval;

  /// Whether to verify the SHA-256 after the last byte arrives.
  final bool verifyChecksum;

  DownloadOptions copyWith({
    int? connections,
    int? targetChunkSize,
    int? maxChunks,
    int? maxRetriesPerChunk,
    Duration? timeout,
    int? bytesPerSecond,
    Map<String, String>? headers,
    Duration? progressInterval,
    Duration? sidecarInterval,
    bool? verifyChecksum,
  }) {
    return DownloadOptions(
      connections: connections ?? this.connections,
      targetChunkSize: targetChunkSize ?? this.targetChunkSize,
      maxChunks: maxChunks ?? this.maxChunks,
      maxRetriesPerChunk: maxRetriesPerChunk ?? this.maxRetriesPerChunk,
      timeout: timeout ?? this.timeout,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      headers: headers ?? this.headers,
      progressInterval: progressInterval ?? this.progressInterval,
      sidecarInterval: sidecarInterval ?? this.sidecarInterval,
      verifyChecksum: verifyChecksum ?? this.verifyChecksum,
    );
  }
}

/// A running download: progress to watch, and pause/cancel to steer it.
class DownloadHandle {
  DownloadHandle._(this._job);

  final _DownloadJob _job;

  /// Throttled progress snapshots. Broadcast, so the CLI and the UI can both
  /// listen without either starving the other.
  Stream<DownloadProgress> get progress => _job.progressStream;

  /// Completes with how the download ended, or with an error on failure.
  Future<DownloadOutcome> get done => _job.done;

  /// Stops after in-flight buffers land, leaving the sidecar ready to resume.
  void pause() => _job.stop(DownloadOutcome.paused);

  /// Stops and discards partial data.
  void cancel() => _job.stop(DownloadOutcome.cancelled);

  /// Changes the aggregate throttle mid-flight.
  set bytesPerSecond(int? value) => _job.limiter.bytesPerSecond = value;
}

/// Multi-connection HTTP downloader with resume and checksum verification.
///
/// Knows nothing about models, sources or targets — it moves bytes from a URL
/// into a file. Everything model-shaped lives above it.
class ChunkedDownloader {
  ChunkedDownloader({HttpClient? client, this.options = const DownloadOptions()})
      : _client = client ?? createHttpClient(),
        _ownsClient = client == null;

  final HttpClient _client;
  final bool _ownsClient;
  final DownloadOptions options;

  /// Builds a client tuned for large downloads.
  ///
  /// `autoUncompress` is off deliberately: a transparently gzipped response
  /// would make byte offsets meaningless and quietly corrupt ranged writes.
  static HttpClient createHttpClient({
    Duration idleTimeout = const Duration(seconds: 30),
    int maxConnectionsPerHost = 32,
    bool useEnvironmentProxy = true,
  }) {
    final client = HttpClient()
      ..autoUncompress = false
      ..idleTimeout = idleTimeout
      ..maxConnectionsPerHost = maxConnectionsPerHost
      ..userAgent = 'silo/0.1 (+https://github.com/LizardKits/silo)';
    if (useEnvironmentProxy) {
      client.findProxy = (Uri uri) => HttpClient.findProxyFromEnvironment(uri);
    }
    return client;
  }

  /// Starts downloading [url] into [target].
  ///
  /// [expectedSha256] wins over whatever the server advertises; pass the digest
  /// from the source's file listing so a lying or misconfigured mirror is
  /// caught. Set [options] per call to override the instance defaults.
  DownloadHandle download({
    required Uri url,
    required File target,
    String? expectedSha256,
    int? expectedSize,
    DownloadOptions? options,
  }) {
    final job = _DownloadJob(
      client: _client,
      url: url,
      target: target,
      expectedSha256: expectedSha256,
      expectedSize: expectedSize,
      options: options ?? this.options,
    );
    job.start();
    return DownloadHandle._(job);
  }

  /// Convenience wrapper that awaits completion.
  Future<DownloadOutcome> downloadToFile({
    required Uri url,
    required File target,
    String? expectedSha256,
    int? expectedSize,
    DownloadOptions? options,
    void Function(DownloadProgress)? onProgress,
  }) {
    final handle = download(
      url: url,
      target: target,
      expectedSha256: expectedSha256,
      expectedSize: expectedSize,
      options: options,
    );
    if (onProgress != null) {
      handle.progress.listen(onProgress);
    }
    return handle.done;
  }

  void close({bool force = false}) {
    if (_ownsClient) _client.close(force: force);
  }
}

/// One download in flight.
class _DownloadJob {
  _DownloadJob({
    required this.client,
    required this.url,
    required this.target,
    required this.expectedSha256,
    required this.expectedSize,
    required this.options,
  }) : limiter = RateLimiter(bytesPerSecond: options.bytesPerSecond);

  final HttpClient client;
  final Uri url;
  final File target;
  final String? expectedSha256;
  final int? expectedSize;
  final DownloadOptions options;
  final RateLimiter limiter;

  final _progressController = StreamController<DownloadProgress>.broadcast();
  final _doneCompleter = Completer<DownloadOutcome>();
  final _rateSamples = <(int, int)>[]; // (micros, receivedBytes)

  late File _sidecar;

  /// Null until the ranged path sets up chunk layout — the single-stream
  /// fallback never has one, so progress accessors must tolerate its absence.
  PartFile? _part;
  final _handles = <RandomAccessFile>[];

  int _nextChunk = 0;
  int _active = 0;
  int _received = 0;

  /// Bytes already on disk when this run started, so progress can distinguish
  /// resumed data from data this run actually fetched.
  int _carriedOver = 0;
  DownloadOutcome? _stopRequested;
  Timer? _ticker;
  DateTime _lastSidecarWrite = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<DownloadProgress> get progressStream => _progressController.stream;
  Future<DownloadOutcome> get done => _doneCompleter.future;

  void stop(DownloadOutcome outcome) => _stopRequested ??= outcome;

  void start() {
    unawaited(_run().then(
      _finish,
      onError: (Object e, StackTrace s) => _fail(e, s),
    ));
  }

  Future<DownloadOutcome> _run() async {
    _sidecar = File('${target.path}.part.json');
    await target.parent.create(recursive: true);

    // Re-adding a model that is already on disk should cost nothing and work
    // offline, so settle that before opening a socket.
    final DownloadOutcome? alreadyDone = await _tryResolveOffline();
    if (alreadyDone != null) return alreadyDone;

    final RemoteFileProbe probe = await probeRemoteFile(
      client,
      url,
      headers: options.headers,
      timeout: options.timeout,
    );

    final int? size = expectedSize ?? probe.size;
    final String? digest = expectedSha256 ?? probe.sha256;

    if (size == null || !probe.acceptsRanges) {
      // No length or no range support: single stream, no resume.
      return _runSingleStream(digest);
    }

    final part =
        await _loadOrCreatePart(size: size, digest: digest, etag: probe.etag);
    _part = part;
    _received = part.received;
    _carriedOver = part.received;
    await _prepareTargetFile(size);

    if (part.isComplete) {
      return _finalize(digest);
    }

    _startTicker();
    final int workers = min(options.connections, part.chunkCount);
    await Future.wait<void>(
      List<Future<void>>.generate(workers, (_) => _worker()),
    );

    if (_stopRequested != null) {
      await _flushSidecar();
      return _stopRequested!;
    }
    if (!part.isComplete) {
      throw DownloadException('download ended with missing chunks', uri: url);
    }
    return _finalize(digest);
  }

  /// Completes the download without any network access when a finished sidecar
  /// and an intact file already describe exactly what was asked for.
  ///
  /// Returns null when anything is unknown or does not line up, in which case
  /// the normal probe-and-fetch path runs.
  Future<DownloadOutcome?> _tryResolveOffline() async {
    final PartFile? part = await PartFile.read(_sidecar);
    if (part == null || !part.isComplete) return null;
    if (!part.matches(url: url, size: expectedSize, sha256: expectedSha256)) {
      return null;
    }
    if (!await target.exists() || await target.length() != part.size) return null;
    // Only skip the network if we can still verify, or verification is off.
    final String? digest = expectedSha256 ?? part.sha256;
    if (options.verifyChecksum && digest == null) return null;

    _part = part;
    _received = part.received;
    _carriedOver = part.received;
    return _finalize(digest);
  }

  Future<PartFile> _loadOrCreatePart({
    required int size,
    required String? digest,
    required String? etag,
  }) async {
    final PartFile? existing = await PartFile.read(_sidecar);
    if (existing != null &&
        existing.matches(url: url, size: size, sha256: digest)) {
      // Trust the sidecar only as far as the file backs it up.
      final int onDisk = await target.exists() ? await target.length() : 0;
      if (onDisk == size) return existing;
    }
    if (existing != null) {
      // Stale sidecar: start clean rather than stitch mismatched bytes.
      await _sidecar.delete().catchError((Object _) => _sidecar);
    }
    return PartFile.fresh(
      url: url,
      size: size,
      chunkSize: _chunkSizeFor(size),
      sha256: digest,
      etag: etag,
    );
  }

  int _chunkSizeFor(int size) {
    var chunkSize = options.targetChunkSize;
    if (size > chunkSize * options.maxChunks) {
      chunkSize = (size + options.maxChunks - 1) ~/ options.maxChunks;
    }
    return max(chunkSize, 1);
  }

  /// Allocates the destination at full size so workers can write at offsets.
  Future<void> _prepareTargetFile(int size) async {
    final raf = await target.open(mode: FileMode.append);
    try {
      if (await raf.length() != size) {
        await raf.truncate(size);
      }
    } finally {
      await raf.close();
    }
  }

  /// Each worker owns its own file handle: `setPosition` + `writeFrom` are two
  /// calls, and sharing one handle across connections would interleave them.
  Future<void> _worker() async {
    final raf = await target.open(mode: FileMode.append);
    _handles.add(raf);
    try {
      while (_stopRequested == null) {
        final int? index = _claimChunk();
        if (index == null) return;
        await _downloadChunk(index, raf);
      }
    } finally {
      _handles.remove(raf);
      await raf.close();
    }
  }

  int? _claimChunk() {
    final part = _part!;
    while (_nextChunk < part.chunkCount) {
      final int index = _nextChunk++;
      if (!part.isChunkComplete(index)) return index;
    }
    return null;
  }

  Future<void> _downloadChunk(int index, RandomAccessFile raf) async {
    var attempt = 0;
    while (true) {
      if (_stopRequested != null) return;
      try {
        await _fetchChunk(index, raf);
        return;
      } on Object catch (error) {
        if (_stopRequested != null) return;
        attempt++;
        if (attempt > options.maxRetriesPerChunk) {
          throw DownloadException(
            'chunk $index failed after $attempt attempts: $error',
            uri: url,
          );
        }
        await Future<void>.delayed(_backoff(attempt));
      }
    }
  }

  /// Exponential backoff with jitter, so a throttled mirror does not get all
  /// connections retrying in lockstep.
  Duration _backoff(int attempt) {
    final int base = 300 * (1 << min(attempt - 1, 5));
    return Duration(milliseconds: base + Random().nextInt(base ~/ 2 + 1));
  }

  Future<void> _fetchChunk(int index, RandomAccessFile raf) async {
    final part = _part!;
    final int start = part.chunkStart(index) + part.done[index];
    final int end = part.chunkEnd(index) - 1;
    if (start > end) return;

    _active++;
    try {
      // Chunk requests follow redirects: HuggingFace hands out presigned CDN
      // URLs that expire, so each attempt re-resolves from the stable URL.
      final request = await client.getUrl(url).timeout(options.timeout);
      request.followRedirects = true;
      request.maxRedirects = 8;
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      options.headers.forEach(request.headers.set);

      final response = await request.close().timeout(options.timeout);
      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw DownloadException(
          'expected 206 for range $start-$end',
          uri: url,
          statusCode: response.statusCode,
        );
      }

      var position = start;
      // Breaking out of `await for` cancels the subscription, which drops the
      // socket — exactly what pause and cancel want.
      await for (final List<int> data in response.timeout(options.timeout)) {
        if (_stopRequested != null) break;
        await limiter.consume(data.length);
        await raf.setPosition(position);
        await raf.writeFrom(data);
        position += data.length;
        part.done[index] += data.length;
        _received += data.length;
        await _maybeFlushSidecar();
      }

      // A short read is a truncated response, not a completed chunk.
      if (_stopRequested == null && part.done[index] < part.chunkLength(index)) {
        throw DownloadException(
          'chunk $index truncated at ${part.done[index]}/'
          '${part.chunkLength(index)} bytes',
          uri: url,
        );
      }
    } finally {
      _active--;
    }
  }

  /// Fallback for servers that will not do ranges: one stream, no resume.
  Future<DownloadOutcome> _runSingleStream(String? digest) async {
    _startTicker();
    final request = await client.getUrl(url).timeout(options.timeout);
    request.followRedirects = true;
    options.headers.forEach(request.headers.set);
    final response = await request.close().timeout(options.timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw DownloadException('unexpected status',
          uri: url, statusCode: response.statusCode);
    }

    final raf = await target.open(mode: FileMode.write);
    _active = 1;
    try {
      await for (final List<int> data in response.timeout(options.timeout)) {
        if (_stopRequested != null) break;
        await limiter.consume(data.length);
        await raf.writeFrom(data);
        _received += data.length;
      }
    } finally {
      _active = 0;
      await raf.close();
    }

    if (_stopRequested != null) return _stopRequested!;
    return _finalize(digest, sizeUnknown: true);
  }

  Future<DownloadOutcome> _finalize(String? digest, {bool sizeUnknown = false}) async {
    final int? expected = sizeUnknown ? null : _part?.size;
    if (expected != null) {
      final int actual = await target.length();
      if (actual != expected) {
        throw DownloadException(
          'size mismatch: expected $expected bytes, file has $actual',
          uri: url,
        );
      }
    }

    if (options.verifyChecksum && digest != null) {
      final String actual = await sha256OfFile(target);
      if (actual != digest) {
        throw ChecksumMismatchException(
          expected: digest,
          actual: actual,
          path: target.path,
        );
      }
    }

    await _sidecar.delete().catchError((Object _) => _sidecar);
    return DownloadOutcome.completed;
  }

  void _startTicker() {
    _ticker = Timer.periodic(options.progressInterval, (_) => _emitProgress());
  }

  void _emitProgress() {
    if (_progressController.isClosed) return;
    final int now = DateTime.now().microsecondsSinceEpoch;
    _rateSamples.add((now, _received));
    // Keep a ~3 second window so the rate reads steady rather than jittery.
    while (_rateSamples.length > 2 && now - _rateSamples.first.$1 > 3000000) {
      _rateSamples.removeAt(0);
    }
    var speed = 0.0;
    if (_rateSamples.length >= 2) {
      final (int t0, int b0) = _rateSamples.first;
      final double seconds = (now - t0) / 1000000;
      if (seconds > 0) speed = (_received - b0) / seconds;
    }

    final part = _part;
    var completed = 0;
    if (part != null) {
      for (var i = 0; i < part.chunkCount; i++) {
        if (part.isChunkComplete(i)) completed++;
      }
    }

    _progressController.add(DownloadProgress(
      received: _received,
      total: part?.size ?? expectedSize,
      bytesPerSecond: speed,
      activeConnections: _active,
      completedChunks: completed,
      totalChunks: part?.chunkCount ?? 1,
      carriedOver: _carriedOver,
    ));
  }

  Future<void> _maybeFlushSidecar() async {
    final DateTime now = DateTime.now();
    if (now.difference(_lastSidecarWrite) < options.sidecarInterval) return;
    _lastSidecarWrite = now;
    await _flushSidecar();
  }

  Future<void> _flushSidecar() async {
    final part = _part;
    if (part == null) return;
    await part.write(_sidecar);
  }

  void _finish(DownloadOutcome outcome) {
    _ticker?.cancel();
    _emitProgress();
    unawaited(_cleanup(discard: outcome == DownloadOutcome.cancelled));
    if (!_doneCompleter.isCompleted) _doneCompleter.complete(outcome);
    unawaited(_progressController.close());
  }

  void _fail(Object error, StackTrace stack) {
    _ticker?.cancel();
    unawaited(_cleanup(discard: false));
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.completeError(error, stack);
    }
    unawaited(_progressController.close());
  }

  Future<void> _cleanup({required bool discard}) async {
    for (final raf in List<RandomAccessFile>.of(_handles)) {
      try {
        await raf.close();
      } on FileSystemException {
        // Already closed by its worker.
      }
    }
    _handles.clear();
    if (discard) {
      await _sidecar.delete().catchError((Object _) => _sidecar);
      await target.delete().catchError((Object _) => target);
    }
  }
}
