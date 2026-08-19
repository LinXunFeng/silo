import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:silo_core/src/download/chunked_downloader.dart';
import 'package:silo_core/src/download/download_types.dart';
import 'package:silo_core/src/download/part_file.dart';
import 'package:silo_core/src/util/sha256.dart';
import 'package:test/test.dart';

/// A deliberately awkward origin server, so the engine meets the behaviours it
/// will meet in the wild without needing the network.
class FakeOrigin {
  FakeOrigin(this.body, {this.sha256OnRedirect = true});

  final Uint8List body;

  /// Mimics HuggingFace: the digest lives on the 302, not on the final hop.
  final bool sha256OnRedirect;

  /// When false, the server answers 200 and ignores `Range` entirely.
  bool supportsRanges = true;

  /// When true, `HEAD` returns 404 the way ModelScope does.
  bool rejectHead = true;

  /// Serve at most this many bytes per ranged response before hanging up,
  /// simulating a mirror that drops connections mid-transfer.
  int? truncateResponsesAt;

  /// Corrupt one byte of every response, to exercise checksum failure.
  bool corrupt = false;

  /// Answer with a gzip-encoded body regardless of Accept-Encoding, the way
  /// HuggingFace does for small non-LFS files.
  bool alwaysGzip = false;

  /// Refuse ranges and serve fewer bytes than the caller was told to expect.
  bool serveShort = false;

  /// Accept-Encoding of the last request, so tests can assert what was asked.
  String? lastAcceptEncoding;

  /// Number of range requests served, for asserting real parallelism/resume.
  int rangeRequests = 0;

  late HttpServer _server;
  Uri get url => Uri.parse('http://${_server.address.host}:${_server.port}/model.gguf');
  String get digest => Sha256.hashBytes(body);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach(_handle));
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    lastAcceptEncoding = request.headers.value(HttpHeaders.acceptEncodingHeader);

    if (request.method == 'HEAD' && rejectHead) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    // First hop redirects, carrying the digest like HuggingFace does.
    if (!request.uri.path.startsWith('/cdn/')) {
      if (sha256OnRedirect) {
        response.headers.set('x-linked-etag', '"$digest"');
        response.headers.set('x-linked-size', '${body.length}');
      }
      response.statusCode = HttpStatus.found;
      response.headers.set(HttpHeaders.locationHeader, '/cdn/model.gguf');
      await response.close();
      return;
    }

    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    if (range == null || !supportsRanges || alwaysGzip || serveShort) {
      response.statusCode = HttpStatus.ok;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'none');

      if (alwaysGzip) {
        final List<int> squeezed = gzip.encode(body);
        response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        response.headers.contentLength = squeezed.length;
        response.add(squeezed);
      } else if (serveShort) {
        final short = Uint8List.sublistView(body, 0, body.length ~/ 2);
        response.headers.contentLength = short.length;
        response.add(short);
      } else {
        response.headers.contentLength = body.length;
        response.add(body);
      }
      await response.close();
      return;
    }

    rangeRequests++;
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
    final int start = int.parse(match.group(1)!);
    final int end = match.group(2)!.isEmpty
        ? body.length - 1
        : min(int.parse(match.group(2)!), body.length - 1);

    var slice = Uint8List.sublistView(body, start, end + 1);
    final int fullLength = slice.length;
    if (truncateResponsesAt != null && slice.length > truncateResponsesAt!) {
      slice = Uint8List.sublistView(slice, 0, truncateResponsesAt!);
    }
    if (corrupt && slice.isNotEmpty) {
      slice = Uint8List.fromList(slice);
      slice[0] = slice[0] ^ 0xff;
    }

    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/${body.length}',
    );
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentLength = fullLength;
    response.add(slice);
    try {
      await response.close();
    } on HttpException {
      // Expected when we deliberately under-deliver the promised length.
    }
  }
}

Uint8List randomBytes(int length, [int seed = 42]) {
  final rnd = Random(seed);
  return Uint8List.fromList(List<int>.generate(length, (_) => rnd.nextInt(256)));
}

void main() {
  late Directory dir;
  late ChunkedDownloader downloader;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('silo_dl_');
    downloader = ChunkedDownloader(
      client: ChunkedDownloader.createHttpClient(useEnvironmentProxy: false),
    );
  });

  tearDown(() async {
    downloader.close(force: true);
    await dir.delete(recursive: true);
  });

  test('downloads in parallel chunks and verifies the digest', () async {
    final origin = FakeOrigin(randomBytes(700 * 1024));
    await origin.start();
    addTearDown(origin.stop);

    final target = File('${dir.path}/model.gguf');
    final outcome = await downloader.downloadToFile(
      url: origin.url,
      target: target,
      options: const DownloadOptions(
        connections: 4,
        targetChunkSize: 64 * 1024,
      ),
    );

    expect(outcome, DownloadOutcome.completed);
    expect(await target.length(), origin.body.length);
    expect(await sha256OfFile(target), origin.digest);
    // 700 KiB / 64 KiB = 11 chunks, so the work really was split up.
    expect(origin.rangeRequests, greaterThanOrEqualTo(11));
    expect(File('${target.path}.part.json').existsSync(), isFalse);
  });

  test('picks up the digest from the redirect hop, not the CDN response', () async {
    final origin = FakeOrigin(randomBytes(200 * 1024));
    await origin.start();
    addTearDown(origin.stop);

    // No digest passed in, so the only way to verify is the 302 header.
    final target = File('${dir.path}/model.gguf');
    await downloader.downloadToFile(
      url: origin.url,
      target: target,
      options: const DownloadOptions(connections: 2, targetChunkSize: 32 * 1024),
    );
    expect(await sha256OfFile(target), origin.digest);
  });

  test('rejects a corrupted download instead of writing a broken model', () async {
    final origin = FakeOrigin(randomBytes(128 * 1024))..corrupt = true;
    await origin.start();
    addTearDown(origin.stop);

    final target = File('${dir.path}/model.gguf');
    await expectLater(
      downloader.downloadToFile(
        url: origin.url,
        target: target,
        expectedSha256: origin.digest,
        options: const DownloadOptions(connections: 2, targetChunkSize: 64 * 1024),
      ),
      throwsA(isA<ChecksumMismatchException>()),
    );
  });

  test('retries truncated responses and still lands the right bytes', () async {
    final origin = FakeOrigin(randomBytes(300 * 1024))
      ..truncateResponsesAt = 20 * 1024;
    await origin.start();
    addTearDown(origin.stop);

    final target = File('${dir.path}/model.gguf');
    final outcome = await downloader.downloadToFile(
      url: origin.url,
      target: target,
      expectedSha256: origin.digest,
      options: const DownloadOptions(
        connections: 2,
        targetChunkSize: 64 * 1024,
        maxRetriesPerChunk: 20,
      ),
    );

    expect(outcome, DownloadOutcome.completed);
    expect(await sha256OfFile(target), origin.digest);
  });

  test('pause leaves a resumable sidecar and resume finishes the file', () async {
    final origin = FakeOrigin(randomBytes(2 * 1024 * 1024));
    await origin.start();
    addTearDown(origin.stop);

    final target = File('${dir.path}/model.gguf');
    const options = DownloadOptions(
      connections: 2,
      targetChunkSize: 64 * 1024,
      sidecarInterval: Duration.zero,
      progressInterval: Duration(milliseconds: 10),
    );

    final handle = downloader.download(
      url: origin.url,
      target: target,
      expectedSha256: origin.digest,
      options: options,
    );

    // Pause as soon as a meaningful amount has landed.
    late StreamSubscription<DownloadProgress> sub;
    sub = handle.progress.listen((p) {
      if (p.received > 128 * 1024) {
        handle.pause();
        unawaited(sub.cancel());
      }
    });

    expect(await handle.done, DownloadOutcome.paused);

    final sidecar = File('${target.path}.part.json');
    expect(sidecar.existsSync(), isTrue);
    final part = (await PartFile.read(sidecar))!;
    expect(part.received, greaterThan(0));
    expect(part.isComplete, isFalse);
    expect(part.sha256, origin.digest);
    // Allocated to full size up front so workers can write at offsets.
    expect(await target.length(), origin.body.length);

    DownloadProgress? last;
    final outcome = await downloader.downloadToFile(
      url: origin.url,
      target: target,
      expectedSha256: origin.digest,
      options: options,
      onProgress: (p) => last = p,
    );

    expect(outcome, DownloadOutcome.completed);
    expect(await sha256OfFile(target), origin.digest);
    // Resume fetched only the missing bytes, not the whole file. Counting
    // requests instead would be flaky: a pause can land with every chunk
    // partially done, so the resume issues just as many (much shorter)
    // requests while transferring far less.
    expect(last!.carriedOver, part.received);
    expect(last!.transferred, origin.body.length - part.received);
    expect(sidecar.existsSync(), isFalse);
  });

  test('resumed bytes are not counted as transferred', () async {
    final origin = FakeOrigin(randomBytes(2 * 1024 * 1024));
    await origin.start();
    addTearDown(origin.stop);

    final target = File('${dir.path}/model.gguf');
    const options = DownloadOptions(
      connections: 2,
      targetChunkSize: 64 * 1024,
      sidecarInterval: Duration.zero,
      progressInterval: Duration(milliseconds: 10),
    );

    final handle = downloader.download(
      url: origin.url,
      target: target,
      expectedSha256: origin.digest,
      options: options,
    );
    late StreamSubscription<DownloadProgress> sub;
    sub = handle.progress.listen((p) {
      if (p.received > 256 * 1024) {
        handle.pause();
        unawaited(sub.cancel());
      }
    });
    expect(await handle.done, DownloadOutcome.paused);

    final int carried = (await PartFile.read(File('${target.path}.part.json')))!
        .received;
    expect(carried, greaterThan(0));

    DownloadProgress? last;
    await downloader.downloadToFile(
      url: origin.url,
      target: target,
      expectedSha256: origin.digest,
      options: options,
      onProgress: (p) => last = p,
    );

    // The second run reports only what it actually pulled down.
    expect(last!.carriedOver, carried);
    expect(last!.received, origin.body.length);
    expect(last!.transferred, origin.body.length - carried);
  });

  test('an already-complete sidecar resolves offline, without any request',
      () async {
    final origin = FakeOrigin(randomBytes(128 * 1024));
    await origin.start();
    addTearDown(origin.stop);

    final target = File('${dir.path}/model.gguf');
    await downloader.downloadToFile(
      url: origin.url,
      target: target,
      expectedSha256: origin.digest,
      options: const DownloadOptions(connections: 2, targetChunkSize: 32 * 1024),
    );

    // Re-running against an intact file must not touch the network at all —
    // not even the one-byte probe.
    final sidecar = File('${target.path}.part.json');
    final part = PartFile.fresh(
      url: origin.url,
      size: origin.body.length,
      chunkSize: 32 * 1024,
      sha256: origin.digest,
    );
    for (var i = 0; i < part.chunkCount; i++) {
      part.done[i] = part.chunkLength(i);
    }
    await part.write(sidecar);

    // Stop the server outright: an offline resolve must still succeed.
    final Uri url = origin.url;
    await origin.stop();

    final outcome = await downloader.downloadToFile(
      url: url,
      target: target,
      expectedSha256: origin.digest,
      options: const DownloadOptions(connections: 2, targetChunkSize: 32 * 1024),
    );
    expect(outcome, DownloadOutcome.completed);
  });

  test('a sidecar describing a different size is discarded', () async {
    final origin = FakeOrigin(randomBytes(128 * 1024));
    await origin.start();
    addTearDown(origin.stop);

    final target = File('${dir.path}/model.gguf');
    final sidecar = File('${target.path}.part.json');
    await PartFile.fresh(
      url: origin.url,
      size: 999999,
      chunkSize: 32 * 1024,
      sha256: 'deadbeef',
    ).write(sidecar);

    final outcome = await downloader.downloadToFile(
      url: origin.url,
      target: target,
      expectedSha256: origin.digest,
      options: const DownloadOptions(connections: 2, targetChunkSize: 32 * 1024),
    );

    expect(outcome, DownloadOutcome.completed);
    expect(await sha256OfFile(target), origin.digest);
  });

  test('cancel discards the partial file and its sidecar', () async {
    final origin = FakeOrigin(randomBytes(2 * 1024 * 1024));
    await origin.start();
    addTearDown(origin.stop);

    final target = File('${dir.path}/model.gguf');
    final handle = downloader.download(
      url: origin.url,
      target: target,
      options: const DownloadOptions(
        connections: 2,
        targetChunkSize: 32 * 1024,
        progressInterval: Duration(milliseconds: 10),
      ),
    );

    late StreamSubscription<DownloadProgress> sub;
    sub = handle.progress.listen((p) {
      if (p.received > 64 * 1024) {
        handle.cancel();
        unawaited(sub.cancel());
      }
    });

    expect(await handle.done, DownloadOutcome.cancelled);
    // Give cleanup a moment to run.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(target.existsSync(), isFalse);
    expect(File('${target.path}.part.json').existsSync(), isFalse);
  });

  test('falls back to a single stream when the server refuses ranges', () async {
    final origin = FakeOrigin(randomBytes(256 * 1024))..supportsRanges = false;
    await origin.start();
    addTearDown(origin.stop);

    final target = File('${dir.path}/model.gguf');
    final outcome = await downloader.downloadToFile(
      url: origin.url,
      target: target,
      expectedSha256: origin.digest,
      options: const DownloadOptions(connections: 8),
    );

    expect(outcome, DownloadOutcome.completed);
    expect(await sha256OfFile(target), origin.digest);
    expect(origin.rangeRequests, 0);
  });

  test('reports progress that reaches the full size', () async {
    final origin = FakeOrigin(randomBytes(512 * 1024));
    await origin.start();
    addTearDown(origin.stop);

    final seen = <DownloadProgress>[];
    await downloader.downloadToFile(
      url: origin.url,
      target: File('${dir.path}/model.gguf'),
      options: const DownloadOptions(
        connections: 4,
        targetChunkSize: 32 * 1024,
        progressInterval: Duration(milliseconds: 5),
      ),
      onProgress: seen.add,
    );

    expect(seen, isNotEmpty);
    expect(seen.last.received, origin.body.length);
    expect(seen.last.total, origin.body.length);
    expect(seen.last.fraction, 1.0);
  });

  group('bodies that are not the file', () {
    test('asks for identity encoding on every download request', () async {
      final origin = FakeOrigin(randomBytes(128 * 1024));
      await origin.start();
      addTearDown(origin.stop);

      await downloader.downloadToFile(
        url: origin.url,
        target: File('${dir.path}/model.gguf'),
        options: const DownloadOptions(connections: 2, targetChunkSize: 32 * 1024),
      );

      expect(origin.lastAcceptEncoding, 'identity');
    });

    test('refuses a gzipped body instead of storing it compressed', () async {
      // HuggingFace compresses small non-LFS files — the config and tokenizer
      // JSON a model will not load without. Stored as-is they are gzip bytes
      // with a .json name, and the tool that reads them fails, not us.
      final origin = FakeOrigin(randomBytes(64 * 1024))..alwaysGzip = true;
      await origin.start();
      addTearDown(origin.stop);

      final target = File('${dir.path}/config.json');
      await expectLater(
        downloader.downloadToFile(
          url: origin.url,
          target: target,
          expectedSize: origin.body.length,
          options: const DownloadOptions(connections: 1),
        ),
        throwsA(isA<DownloadException>()),
      );
    });

    test('catches a short file even with no digest to check against', () async {
      // Non-LFS files publish no SHA-256, so the declared size is the only
      // evidence available. Skipping the check on the single-stream path is
      // what let compressed files through silently.
      final origin = FakeOrigin(randomBytes(64 * 1024))..serveShort = true;
      await origin.start();
      addTearDown(origin.stop);

      await expectLater(
        downloader.downloadToFile(
          url: origin.url,
          target: File('${dir.path}/config.json'),
          expectedSize: origin.body.length,
          options: const DownloadOptions(connections: 1),
        ),
        throwsA(isA<DownloadException>()),
      );
    });

    test('a single-stream download of the right length still succeeds', () async {
      final origin = FakeOrigin(randomBytes(64 * 1024))..supportsRanges = false;
      await origin.start();
      addTearDown(origin.stop);

      final target = File('${dir.path}/config.json');
      final outcome = await downloader.downloadToFile(
        url: origin.url,
        target: target,
        expectedSize: origin.body.length,
        expectedSha256: origin.digest,
        options: const DownloadOptions(connections: 1),
      );

      expect(outcome, DownloadOutcome.completed);
      expect(await target.length(), origin.body.length);
    });
  });

}
