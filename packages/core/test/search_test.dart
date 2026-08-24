import 'dart:convert';
import 'dart:io';

import 'package:silo_core/silo_core.dart';
import 'package:test/test.dart';

/// A hub that answers both search dialects: HuggingFace's `GET /api/models`
/// with a tag filter, and ModelScope's `PUT /api/v1/dolphin/models`.
class FakeSearchHub {
  FakeSearchHub();

  late HttpServer _server;

  /// Requests seen, so tests can assert how the filter was expressed.
  final List<String> requests = <String>[];

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    requests.add('${request.method} ${request.uri}');

    if (request.uri.path == '/api/models') {
      final String? filter = request.uri.queryParameters['filter'];
      final entries = <Map<String, Object?>>[
        if (filter == 'gguf' || filter == null)
          <String, Object?>{
            'id': 'acme/Demo-GGUF',
            'downloads': 500,
            'likes': 10,
            'tags': <String>['gguf'],
          },
        if (filter == 'mlx' || filter == null)
          <String, Object?>{
            'id': 'acme/Demo-MLX-8bit',
            'downloads': 300,
            'likes': 5,
            'tags': <String>['mlx', 'safetensors'],
          },
        if (filter == null)
          <String, Object?>{
            'id': 'acme/Demo',
            'downloads': 9000,
            'likes': 99,
            'tags': <String>['safetensors', 'transformers'],
          },
        // Junk the parser must survive.
        <String, Object?>{'id': 'no-slash'},
        <String, Object?>{'downloads': 1},
      ];
      response.add(utf8.encode(jsonEncode(entries)));
      await response.close();
      return;
    }

    if (request.uri.path == '/api/v1/dolphin/models') {
      await utf8.decoder.bind(request).join();
      response.add(utf8.encode(jsonEncode(<String, Object?>{
        'Code': 200,
        'Data': <String, Object?>{
          'Model': <String, Object?>{
            'Models': <Object>[
              <String, Object?>{
                'Path': 'acme',
                'Name': 'Demo-GGUF',
                'Downloads': 4000,
                'Stars': 12,
                'ChineseName': '演示模型',
              },
              <String, Object?>{
                'Path': 'acme',
                'Name': 'Local-Only-GGUF',
                'Downloads': 7,
                'Stars': 0,
                'ChineseName': '',
              },
              <String, Object?>{'Path': '', 'Name': 'broken'},
            ],
          },
        },
      })));
      await response.close();
      return;
    }

    response.statusCode = HttpStatus.notFound;
    await response.close();
  }
}

void main() {
  late FakeSearchHub hub;
  late HttpClient client;

  setUp(() async {
    hub = FakeSearchHub();
    await hub.start();
    client = ChunkedDownloader.createHttpClient(useEnvironmentProxy: false);
  });

  tearDown(() async {
    client.close(force: true);
    await hub.stop();
  });

  group('HuggingFace search', () {
    test('parses hits and skips malformed entries', () async {
      final source = HuggingFaceSource(endpoint: hub.base, client: client);
      final results = await source.search('demo');

      expect(results.map((r) => r.ref.id),
          containsAll(<String>['acme/Demo-GGUF', 'acme/Demo']));
      expect(results.any((r) => r.ref.id == 'no-slash'), isFalse);
      expect(results.first.downloads, 9000, reason: 'sorted by downloads');
    });

    test('asks the hub for gguf and mlx tags when local formats are wanted',
        () async {
      final source = HuggingFaceSource(endpoint: hub.base, client: client);
      final results = await source.search('demo', localFormatsOnly: true);

      expect(hub.requests.where((r) => r.contains('filter=gguf')), hasLength(1));
      expect(hub.requests.where((r) => r.contains('filter=mlx')), hasLength(1));
      // The transformers original is only returned by the unfiltered query.
      expect(results.map((r) => r.ref.id), isNot(contains('acme/Demo')));
      expect(results.map((r) => r.ref.id),
          containsAll(<String>['acme/Demo-GGUF', 'acme/Demo-MLX-8bit']));
    });
  });

  group('ModelScope search', () {
    test('reads Path and Name, and keeps the Chinese label', () async {
      final source = ModelScopeSource(endpoint: hub.base, client: client);
      final results = await source.search('demo');

      expect(results.map((r) => r.ref.id),
          containsAll(<String>['acme/Demo-GGUF', 'acme/Local-Only-GGUF']));
      expect(results.first.description, '演示模型');
      expect(results.any((r) => r.ref.author.isEmpty), isFalse);
    });
  });

  group('format inference', () {
    test('reads the format off the name or the tags', () {
      const gguf = ModelSearchResult(
        ref: ModelRef('acme', 'Thing-GGUF'),
        sourceId: 'x',
      );
      expect(gguf.formats, contains('gguf'));
      expect(gguf.isLocalReady, isTrue);

      const plain = ModelSearchResult(
        ref: ModelRef('acme', 'Thing'),
        sourceId: 'x',
        tags: <String>['safetensors'],
      );
      expect(plain.isLocalReady, isFalse);
    });
  });

  group('merged search', () {
    late SiloLibrary library;
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('silo_search_');
      library = SiloLibrary(
        store: BlobStore(Directory('${tmp.path}/store')),
        sources: <ModelSource>[
          HuggingFaceSource(endpoint: hub.base, client: client),
          ModelScopeSource(endpoint: hub.base, client: client),
        ],
        targets: const <DownloadTarget>[],
      );
    });

    tearDown(() async {
      library.close();
      await tmp.delete(recursive: true);
    });

    test('folds the same repo across sources and names both', () async {
      final results = await library.search('demo');

      final shared =
          results.firstWhere((r) => r.ref.id == 'acme/Demo-GGUF');
      expect(shared.sourceIds, containsAll(<String>['huggingface', 'modelscope']));
      expect(results.where((r) => r.ref.id == 'acme/Demo-GGUF'), hasLength(1));
    });

    test('keeps a hit only one source returned', () async {
      final results = await library.search('demo');
      final msOnly =
          results.firstWhere((r) => r.ref.id == 'acme/Local-Only-GGUF');
      expect(msOnly.sourceIds, <String>['modelscope']);
    });

    test('sorts by downloads and honours the limit', () async {
      final results = await library.search('demo', limit: 2);
      expect(results, hasLength(2));
      expect(
        results.first.downloads,
        greaterThanOrEqualTo(results.last.downloads),
      );
    });

    test('local-formats-only drops the transformers original', () async {
      final results = await library.search('demo', localFormatsOnly: true);
      expect(results.map((r) => r.ref.id), isNot(contains('acme/Demo')));
      expect(results, isNotEmpty);
    });

    test('a source whose search fails does not take the search down', () async {
      final broken = SiloLibrary(
        store: BlobStore(Directory('${tmp.path}/store2')),
        sources: <ModelSource>[
          HuggingFaceSource(
            endpoint: Uri.parse('http://127.0.0.1:1'),
            client: client,
          ),
          ModelScopeSource(endpoint: hub.base, client: client),
        ],
        targets: const <DownloadTarget>[],
      );
      addTearDown(broken.close);

      final logs = <String>[];
      final results = await broken.search('demo', onLog: logs.add);

      expect(results, isNotEmpty, reason: 'the working source still answered');
      expect(logs, isNotEmpty, reason: 'the failure is reported, not hidden');
    });
  });
}
