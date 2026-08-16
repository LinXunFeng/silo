import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:silo_core/silo_core.dart';
import 'package:test/test.dart';

/// A minimal hub that serves one safetensors-shaped repository.
class FakeHub {
  FakeHub();

  final Map<String, Uint8List> files = <String, Uint8List>{};
  late HttpServer _server;

  int get port => _server.port;

  Uri get base => Uri.parse('http://127.0.0.1:$port');

  String digestOf(String path) => Sha256.hashBytes(files[path]!);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach(_handle));
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final String path = request.uri.path;

    if (path.contains('/tree/')) {
      response.add(utf8.encode(jsonEncode(<Object>[
        for (final entry in files.entries)
          <String, Object?>{
            'type': 'file',
            'oid': 'a' * 40,
            'size': entry.value.length,
            'lfs': <String, Object?>{
              'oid': Sha256.hashBytes(entry.value),
              'size': entry.value.length,
            },
            'path': entry.key,
          },
      ])));
      await response.close();
      return;
    }

    // /{author}/{repo}/resolve/{rev}/{file}
    final int marker = request.uri.pathSegments.indexOf('resolve');
    if (marker < 0) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final String name =
        request.uri.pathSegments.sublist(marker + 2).join('/');
    final Uint8List? body = files[name];
    if (body == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    if (range == null) {
      response.headers.contentLength = body.length;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.add(body);
      await response.close();
      return;
    }

    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
    final int start = int.parse(match.group(1)!);
    final int end = match.group(2)!.isEmpty
        ? body.length - 1
        : min(int.parse(match.group(2)!), body.length - 1);
    final slice = Uint8List.sublistView(body, start, end + 1);

    response.statusCode = HttpStatus.partialContent;
    response.headers
        .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${body.length}');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentLength = slice.length;
    response.add(slice);
    await response.close();
  }
}

Uint8List bytes(int length, int seed) {
  final rnd = Random(seed);
  return Uint8List.fromList(List<int>.generate(length, (_) => rnd.nextInt(256)));
}

void main() {
  late Directory tmp;
  late FakeHub hub;
  late SiloLibrary library;
  late BlobStore store;
  late LmStudioTarget target;

  const ref = ModelRef('acme', 'Demo-MLX-8bit');

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('silo_add_');
    hub = FakeHub()
      ..files['config.json'] = bytes(512, 1)
      ..files['tokenizer.json'] = bytes(4096, 2)
      ..files['model-00001-of-00002.safetensors'] = bytes(512 * 1024, 3)
      ..files['model-00002-of-00002.safetensors'] = bytes(512 * 1024, 4);
    await hub.start();

    store = BlobStore(Directory('${tmp.path}/silo'));
    target = LmStudioTarget(root: Directory('${tmp.path}/.lmstudio/models'));
    library = SiloLibrary(
      store: store,
      sources: <ModelSource>[HuggingFaceSource(endpoint: hub.base)],
      targets: <DownloadTarget>[target],
      options: const DownloadOptions(
        connections: 2,
        targetChunkSize: 32 * 1024,
        progressInterval: Duration(milliseconds: 10),
        sidecarInterval: Duration.zero,
      ),
    );
  });

  tearDown(() async {
    library.close();
    await hub.stop();
    await tmp.delete(recursive: true);
  });

  test('add pulls every file of a safetensors variant', () async {
    final result = await library.add(ref, probeSourceSpeed: false);

    expect(result.isComplete, isTrue);
    expect(result.entry.files.map((f) => f.name).toSet(), <String>{
      'config.json',
      'tokenizer.json',
      'model-00001-of-00002.safetensors',
      'model-00002-of-00002.safetensors',
    });
    expect(await store.listBlobs(), hasLength(4));

    final catalog = await library.readCatalog();
    expect(catalog.entries, hasLength(1));
  });

  test('link hard-links the whole variant into LM Studio layout', () async {
    await library.add(ref, probeSourceSpeed: false);
    final results = await library.link(ref, targetIds: <String>['lmstudio']);

    final InstallResult install = results.single;
    expect(install.links, hasLength(4));
    expect(install.bytesOnDisk, 0, reason: 'hard links cost nothing');

    final dir = Directory('${target.root.path}/acme/Demo-MLX-8bit');
    expect(dir.existsSync(), isTrue);
    expect(await dir.list().length, 4);
  });

  test('a second add of the same content downloads nothing', () async {
    await library.add(ref, probeSourceSpeed: false);
    final second = await library.add(ref, probeSourceSpeed: false);

    expect(second.isComplete, isTrue);
    expect(second.downloadedBytes, 0);
    expect(second.dedupedBytes, greaterThan(0));
  });

  test('pause stops the run and catalogues nothing', () async {
    final handle = AddHandle();
    var seen = 0;

    final future = library.add(
      ref,
      probeSourceSpeed: false,
      handle: handle,
      onProgress: (p) {
        seen++;
        if (p.receivedBytes > 64 * 1024) handle.pause();
      },
    );

    final result = await future;
    expect(seen, greaterThan(0));
    expect(result.outcome, DownloadOutcome.paused);
    expect(result.isComplete, isFalse);

    // Nothing half-installed is recorded.
    final catalog = await library.readCatalog();
    expect(catalog.entries, isEmpty);
  });

  test('a paused add resumes and completes on the next run', () async {
    final handle = AddHandle();
    final paused = await library.add(
      ref,
      probeSourceSpeed: false,
      handle: handle,
      onProgress: (p) {
        if (p.receivedBytes > 64 * 1024) handle.pause();
      },
    );
    expect(paused.outcome, DownloadOutcome.paused);

    final resumed = await library.add(ref, probeSourceSpeed: false);
    expect(resumed.isComplete, isTrue);
    expect(resumed.resumedBytes, greaterThan(0),
        reason: 'partial data from the paused run should be reused');

    final catalog = await library.readCatalog();
    expect(catalog.entries, hasLength(1));
  });

  test('cancel stops the run without cataloguing', () async {
    final handle = AddHandle();
    final result = await library.add(
      ref,
      probeSourceSpeed: false,
      handle: handle,
      onProgress: (p) {
        if (p.receivedBytes > 64 * 1024) handle.cancel();
      },
    );

    expect(result.outcome, DownloadOutcome.cancelled);
    expect((await library.readCatalog()).entries, isEmpty);
  });

  test('a handle stopped before starting never opens a download', () async {
    final handle = AddHandle()..cancel();
    final result =
        await library.add(ref, probeSourceSpeed: false, handle: handle);

    expect(result.outcome, DownloadOutcome.cancelled);
    expect(result.downloadedBytes, 0);
    expect(await store.listBlobs(), isEmpty);
  });

  test('gc reclaims blobs once a variant is forgotten', () async {
    await library.add(ref, probeSourceSpeed: false);
    expect(await library.forget(ref), isTrue);

    final result = await library.gc();
    expect(result.blobs, 4);
    expect(result.bytes, greaterThan(0));
    expect(await store.listBlobs(), isEmpty);
  });
}
