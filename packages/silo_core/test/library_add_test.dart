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
    expect(result.freedBytes, greaterThan(0));
    expect(result.retainedBytes, 0, reason: 'nothing was linked into a tool');
    expect(await store.listBlobs(), isEmpty);
  });

  group('unlink', () {
    Future<Directory> installedDir() async {
      await library.add(ref, probeSourceSpeed: false);
      await library.link(ref, targetIds: <String>['lmstudio']);
      return Directory('${target.root.path}/acme/Demo-MLX-8bit');
    }

    test('removes the files it placed and prunes the directory', () async {
      final dir = await installedDir();
      expect(await dir.list().length, 4);

      final results = await library.unlink(ref);

      expect(results.single.targetId, 'lmstudio');
      expect(results.single.removed, hasLength(4));
      expect(results.single.skipped, isEmpty);
      expect(dir.existsSync(), isFalse, reason: 'empty dirs are pruned');
    });

    test('leaves the blobs alone — only gc removes those', () async {
      await installedDir();
      await library.unlink(ref);

      expect(await store.listBlobs(), hasLength(4));
      expect((await library.readCatalog()).entries, hasLength(1));
    });

    test('drops the link records so the catalogue stops claiming them',
        () async {
      await installedDir();
      expect((await library.readCatalog()).links, hasLength(4));

      await library.unlink(ref);
      expect((await library.readCatalog()).links, isEmpty);
    });

    test('refuses to delete a file the user replaced by hand', () async {
      final dir = await installedDir();
      final planted = File('${dir.path}/config.json');

      // Replace one link with an unrelated file at the same path.
      await planted.delete();
      await planted.writeAsBytes(bytes(64, 99));

      final results = await library.unlink(ref);

      expect(results.single.skipped, hasLength(1));
      expect(results.single.skipped.single, endsWith('config.json'));
      expect(results.single.removed, hasLength(3));
      expect(planted.existsSync(), isTrue,
          reason: 'a file Silo did not place must survive');
    });

    test('a missing file is not an error', () async {
      final dir = await installedDir();
      await File('${dir.path}/config.json').delete();

      final results = await library.unlink(ref);
      expect(results.single.removed, hasLength(3));
      expect(results.single.skipped, isEmpty);
    });

    test('only the named targets are touched', () async {
      await installedDir();

      final results = await library.unlink(ref, targetIds: <String>['nope']);
      expect(results, isEmpty);
      expect((await library.readCatalog()).links, hasLength(4));
    });

    test('forget unlinks first, so gc can actually free the space', () async {
      final dir = await installedDir();
      expect(await dir.list().length, 4);

      expect(await library.forget(ref), isTrue);
      expect(dir.existsSync(), isFalse);

      final result = await library.gc();
      expect(result.blobs, 4);
      expect(result.retainedBytes, 0,
          reason: 'nothing still links the blobs, so the space is really back');
      expect(result.freedBytes, greaterThan(0));
    });

    test('forget can keep the installed files when asked', () async {
      final dir = await installedDir();

      expect(
        await library.forget(ref, unlinkFirst: false),
        isTrue,
      );
      expect(dir.existsSync(), isTrue);

      // And now gc is honest about freeing nothing: the tool still holds them.
      final result = await library.gc();
      expect(result.freedBytes, 0);
      expect(result.retainedBytes, greaterThan(0));
    });
  });


  group('unindexed weight files', () {
    /// A repository shaped like an MTP build: an indexed model beside an extra
    /// weight artifact meant for a custom runtime.
    Future<void> serveMtpRepo() async {
      hub.files.clear();
      hub.files['model-00001-of-00002.safetensors'] = bytes(4096, 30);
      hub.files['model-00002-of-00002.safetensors'] = bytes(4096, 31);
      hub.files['model-vision.safetensors'] = bytes(2048, 32);
      hub.files['mtp.safetensors'] = bytes(1024, 33);
      hub.files['config.json'] = bytes(128, 34);
      hub.files['model.safetensors.index.json'] = Uint8List.fromList(
        utf8.encode(jsonEncode(<String, Object?>{
          'metadata': <String, Object?>{'total_size': 10240},
          'weight_map': <String, Object?>{
            'a': 'model-00001-of-00002.safetensors',
            'b': 'model-00002-of-00002.safetensors',
            'v': 'model-vision.safetensors',
          },
        })),
      );
    }

    Future<Directory> install() async {
      await serveMtpRepo();
      await library.add(ref, probeSourceSpeed: false);
      await library.link(ref, targetIds: <String>['lmstudio']);
      return Directory('${target.root.path}/acme/Demo-MLX-8bit');
    }

    test('keeps every file in the store', () async {
      await install();
      // The library is a mirror; completeness is the point.
      expect(await store.listBlobs(), hasLength(6));
      final entry = (await library.readCatalog()).entries.single;
      expect(entry.files.map((f) => f.name), contains('mtp.safetensors'));
    });

    test('does not place a weight file the index does not claim', () async {
      final dir = await install();
      final names = await dir.list().map((e) => e.uri.pathSegments.last).toList();

      // LM Studio's MLX backend globs *.safetensors and merges them, so an
      // unclaimed one makes the whole model fail to load.
      expect(names, isNot(contains('mtp.safetensors')));
      expect(
        names,
        containsAll(<String>[
          'model-00001-of-00002.safetensors',
          'model-00002-of-00002.safetensors',
          'model-vision.safetensors',
          'config.json',
          'model.safetensors.index.json',
        ]),
      );
    });

    test('re-linking removes a file placed before the rule existed', () async {
      final dir = await install();

      // Simulate the older behaviour: put the unclaimed weight in place and
      // record it the way an earlier link would have.
      final entry = (await library.readCatalog()).entries.single;
      final mtp = entry.files.firstWhere((f) => f.name == 'mtp.safetensors');
      final planted = File('${dir.path}/mtp.safetensors');
      await store.linkTo(mtp.sha256, planted);
      final catalog = await library.readCatalog();
      catalog.recordLinks(<LinkRecord>[
        LinkRecord(
          entryKey: entry.key,
          targetId: 'lmstudio',
          sha256: mtp.sha256,
          path: planted.path,
          hardLinked: true,
        ),
      ]);
      await catalog.write(library.catalogFile);
      expect(planted.existsSync(), isTrue);

      await library.link(ref, targetIds: <String>['lmstudio']);

      expect(planted.existsSync(), isFalse, reason: 'linking converges');
      expect(
        (await library.readCatalog())
            .links
            .any((l) => l.path == planted.path),
        isFalse,
      );
      // The blob stays: the store still holds what the repository published.
      expect(await store.has(mtp.sha256), isTrue);
    });

    test('a repository with no index is left completely alone', () async {
      hub.files.clear();
      hub.files['model.safetensors'] = bytes(4096, 40);
      hub.files['extra.safetensors'] = bytes(1024, 41);
      hub.files['config.json'] = bytes(128, 42);

      await library.add(ref, probeSourceSpeed: false);
      await library.link(ref, targetIds: <String>['lmstudio']);

      final dir = Directory('${target.root.path}/acme/Demo-MLX-8bit');
      final names = await dir.list().map((e) => e.uri.pathSegments.last).toList();
      expect(names, contains('extra.safetensors'),
          reason: 'no manifest means nothing to check against');
    });
  });

}
