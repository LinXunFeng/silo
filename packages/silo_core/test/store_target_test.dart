import 'dart:io';
import 'dart:typed_data';

import 'package:silo_core/silo_core.dart';
import 'package:test/test.dart';

Uint8List bytes(int length, int seed) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 31 + seed) & 0xff));

void main() {
  late Directory tmp;
  late BlobStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('silo_store_');
    store = BlobStore(Directory('${tmp.path}/silo'));
    await store.ensureCreated();
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<String> stage(String name, Uint8List data) async {
    final digest = Sha256.hashBytes(data);
    final staged = store.stagingFile(digest);
    await staged.writeAsBytes(data);
    await store.ingest(staged, digest);
    return digest;
  }

  group('BlobStore', () {
    test('ingests under the digest and fans out by prefix', () async {
      final data = bytes(4096, 1);
      final digest = await stage('a.gguf', data);

      final blob = store.blobFile(digest);
      expect(await blob.exists(), isTrue);
      expect(blob.path, endsWith('${digest.substring(0, 2)}/$digest'));
      expect(await blob.readAsBytes(), data);
      expect(await store.has(digest), isTrue);
    });

    test('ingesting the same content twice keeps exactly one copy', () async {
      final data = bytes(4096, 2);
      final first = await stage('a.gguf', data);
      final second = await stage('b.gguf', data);

      expect(first, second);
      expect(await store.listBlobs(), hasLength(1));
      expect(await store.totalSize(), data.length);
    });

    test('refuses to ingest content that does not match its digest', () async {
      final staged = store.stagingFile('0' * 64);
      await staged.writeAsBytes(bytes(100, 3));
      await expectLater(
        store.ingest(staged, '0' * 64, verify: true),
        throwsArgumentError,
      );
    });

    test('linkTo creates a real hard link, not a copy', () async {
      final data = bytes(64 * 1024, 4);
      final digest = await stage('model.gguf', data);
      final destination = File('${tmp.path}/tool/model.gguf');

      final result = await store.linkTo(digest, destination);

      expect(result.method, LinkMethod.hardLink);
      expect(result.bytesOnDisk, 0);
      expect(await destination.readAsBytes(), data);

      // The decisive check: same inode as the blob.
      final String? blobInode = await inodeIdOf(store.blobFile(digest).path);
      final String? linkInode = await inodeIdOf(destination.path);
      expect(blobInode, isNotNull);
      expect(linkInode, blobInode);
    });

    test('linking to many destinations does not multiply disk usage', () async {
      final data = bytes(256 * 1024, 5);
      final digest = await stage('model.gguf', data);

      for (final tool in <String>['lmstudio', 'llamacpp', 'scratch']) {
        final result =
            await store.linkTo(digest, File('${tmp.path}/$tool/model.gguf'));
        expect(result.method, LinkMethod.hardLink);
      }

      // Three visible files, one physical block allocation.
      final du = await Process.run('du', <String>['-sk', tmp.path]);
      final int kilobytes =
          int.parse((du.stdout as String).trim().split(RegExp(r'\s+')).first);
      // 256 KiB stored once plus filesystem overhead; three copies would be
      // 768 KiB or more.
      expect(kilobytes, lessThan(600));
    });

    test('relinking an existing link is reported, not redone', () async {
      final digest = await stage('m.gguf', bytes(1024, 6));
      final destination = File('${tmp.path}/tool/m.gguf');

      expect((await store.linkTo(digest, destination)).method,
          LinkMethod.hardLink);
      expect((await store.linkTo(digest, destination)).method,
          LinkMethod.alreadyLinked);
    });

    test('linking replaces a stale file at the destination', () async {
      final digest = await stage('m.gguf', bytes(1024, 7));
      final destination = File('${tmp.path}/tool/m.gguf');
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(bytes(10, 99));

      final result = await store.linkTo(digest, destination);
      expect(result.method, LinkMethod.hardLink);
      expect(await destination.length(), 1024);
    });

    test('linking an unknown blob fails loudly', () async {
      await expectLater(
        store.linkTo('f' * 64, File('${tmp.path}/tool/x.gguf')),
        throwsStateError,
      );
    });

    test('pruneStaging clears interrupted downloads', () async {
      await store.stagingFile('a' * 64).writeAsBytes(bytes(2048, 8));
      expect(await store.pruneStaging(), 2048);
      expect(await store.tempDir.list().isEmpty, isTrue);
    });
  });

  group('LmStudioTarget', () {
    late LmStudioTarget target;

    setUp(() {
      target = LmStudioTarget(root: Directory('${tmp.path}/.lmstudio/models'));
    });

    test('lays files out as {author}/{repo}/{file}', () {
      expect(
        target.relativePathFor(
          const ModelRef('Qwen', 'Qwen2.5-7B-Instruct-GGUF'),
          'qwen2.5-7b-instruct-q4_k_m.gguf',
        ),
        'Qwen/Qwen2.5-7B-Instruct-GGUF/qwen2.5-7b-instruct-q4_k_m.gguf',
      );
    });

    test('flattens nested repo paths to keep the depth exactly right', () {
      expect(
        target.relativePathFor(
          const ModelRef('Author', 'Repo'),
          'subdir/model-q4_k_m.gguf',
        ),
        'Author/Repo/model-q4_k_m.gguf',
      );
    });

    test('installs a sharded variant plus its mmproj by hard link', () async {
      const ref = ModelRef('Author', 'Vision-GGUF');
      final files = <TargetFile>[
        TargetFile(
          sha256: await stage('p1', bytes(2048, 10)),
          relativePath: 'model-00001-of-00002.gguf',
        ),
        TargetFile(
          sha256: await stage('p2', bytes(2048, 11)),
          relativePath: 'model-00002-of-00002.gguf',
        ),
        TargetFile(
          sha256: await stage('mm', bytes(512, 12)),
          relativePath: 'mmproj-model-f16.gguf',
        ),
      ];

      final result = await target.install(ref, files, store);

      expect(result.links, hasLength(3));
      expect(result.hardLinkCount, 3);
      expect(result.bytesOnDisk, 0);
      expect(result.apparentSize, 2048 + 2048 + 512);

      final dir = Directory('${target.root.path}/Author/Vision-GGUF');
      final names = await dir
          .list()
          .map((e) => e.uri.pathSegments.last)
          .toList();
      expect(
        names..sort(),
        <String>[
          'mmproj-model-f16.gguf',
          'model-00001-of-00002.gguf',
          'model-00002-of-00002.gguf',
        ],
      );
    });

    test('scanInstalled finds what is already on disk', () async {
      const ref = ModelRef('Qwen', 'Demo-GGUF');
      await target.install(ref, <TargetFile>[
        TargetFile(
          sha256: await stage('m', bytes(4096, 13)),
          relativePath: 'demo-q4_k_m.gguf',
        ),
      ], store);

      final installed = await target.scanInstalled();
      expect(installed, hasLength(1));
      expect(installed.single.ref, ref);
      expect(installed.single.totalSize, 4096);
    });

    test('uninstall removes files and prunes empty directories', () async {
      const ref = ModelRef('Qwen', 'Demo-GGUF');
      final files = <TargetFile>[
        TargetFile(
          sha256: await stage('m', bytes(4096, 14)),
          relativePath: 'demo-q4_k_m.gguf',
        ),
      ];
      await target.install(ref, files, store);

      expect(await target.uninstall(ref, files), 1);
      expect(
        Directory('${target.root.path}/Qwen/Demo-GGUF').existsSync(),
        isFalse,
      );
      // The blob survives; only gc removes those.
      expect(await store.listBlobs(), hasLength(1));
    });
  });

  group('Catalog', () {
    test('round-trips through JSON', () async {
      final file = File('${tmp.path}/catalog.json');
      final catalog = Catalog()
        ..upsert(CatalogEntry(
          ref: const ModelRef('Qwen', 'Demo-GGUF'),
          variant: 'demo-q4_k_m',
          sourceId: 'hf-mirror',
          revision: 'main',
          addedAt: DateTime.parse('2026-08-16T10:00:00Z'),
          files: <CatalogFile>[
            CatalogFile(name: 'demo-q4_k_m.gguf', sha256: 'a' * 64, size: 100),
          ],
        ));
      await catalog.write(file);

      final reloaded = await Catalog.read(file);
      expect(reloaded.entries, hasLength(1));
      final entry = reloaded.entries.single;
      expect(entry.ref.id, 'Qwen/Demo-GGUF');
      expect(entry.variant, 'demo-q4_k_m');
      expect(entry.sourceId, 'hf-mirror');
      expect(entry.totalSize, 100);
      expect(reloaded.referencedBlobs(), <String>{'a' * 64});
    });

    test('upsert replaces rather than duplicates', () {
      CatalogEntry make(int size) => CatalogEntry(
            ref: const ModelRef('A', 'B'),
            variant: 'v',
            sourceId: 's',
            revision: 'main',
            addedAt: DateTime.now(),
            files: <CatalogFile>[
              CatalogFile(name: 'f', sha256: 'a' * 64, size: size),
            ],
          );

      final catalog = Catalog()..upsert(make(1));
      catalog.upsert(make(2));
      expect(catalog.entries, hasLength(1));
      expect(catalog.entries.single.totalSize, 2);
    });

    test('an unreadable catalog degrades to empty instead of throwing', () async {
      final file = File('${tmp.path}/broken.json');
      await file.writeAsString('{ not json');
      expect((await Catalog.read(file)).entries, isEmpty);
    });
  });
}
