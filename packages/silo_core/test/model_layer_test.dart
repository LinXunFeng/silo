import 'dart:convert';
import 'dart:io';

import 'package:silo_core/src/download/chunked_downloader.dart';
import 'package:silo_core/src/model/model_ref.dart';
import 'package:silo_core/src/model/model_variant.dart';
import 'package:silo_core/src/model/remote_file.dart';
import 'package:silo_core/src/source/huggingface_source.dart';
import 'package:silo_core/src/source/model_source.dart';
import 'package:silo_core/src/source/modelscope_source.dart';
import 'package:test/test.dart';

RemoteFile f(String path, {int size = 100, String? sha256}) =>
    RemoteFile(path: path, size: size, sha256: sha256);

void main() {
  group('ModelRef.parse', () {
    test('accepts author/repo', () {
      final ref = ModelRef.parse('Qwen/Qwen2.5-7B-Instruct-GGUF');
      expect(ref.author, 'Qwen');
      expect(ref.repo, 'Qwen2.5-7B-Instruct-GGUF');
      expect(ref.id, 'Qwen/Qwen2.5-7B-Instruct-GGUF');
    });

    test('accepts hub URLs', () {
      expect(
        ModelRef.parse('https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF'),
        const ModelRef('Qwen', 'Qwen2.5-7B-Instruct-GGUF'),
      );
      expect(
        ModelRef.parse(
            'https://hf-mirror.com/Qwen/Qwen2.5-7B-Instruct-GGUF/tree/main'),
        const ModelRef('Qwen', 'Qwen2.5-7B-Instruct-GGUF'),
      );
      expect(
        ModelRef.parse('https://www.modelscope.cn/models/Qwen/Qwen2.5-7B-Instruct-GGUF'),
        const ModelRef('Qwen', 'Qwen2.5-7B-Instruct-GGUF'),
      );
    });

    test('rejects anything without both halves', () {
      expect(() => ModelRef.parse('qwen'), throwsFormatException);
      expect(() => ModelRef.parse('a/b/c'), throwsFormatException);
      expect(() => ModelRef.parse(''), throwsFormatException);
    });
  });

  group('groupVariants (GGUF)', () {
    test('collapses shards into one ordered variant', () {
      final variants = groupVariants(<RemoteFile>[
        f('model-00003-of-00003.gguf', size: 3),
        f('model-00001-of-00003.gguf', size: 1),
        f('model-00002-of-00003.gguf', size: 2),
      ]);

      expect(variants, hasLength(1));
      final v = variants.single;
      expect(v.name, 'model');
      expect(v.isSharded, isTrue);
      expect(v.parts.map((p) => p.name), <String>[
        'model-00001-of-00003.gguf',
        'model-00002-of-00003.gguf',
        'model-00003-of-00003.gguf',
      ]);
      expect(v.totalSize, 6);
    });

    test('attaches mmproj to every variant', () {
      final variants = groupVariants(<RemoteFile>[
        f('llava-q4_k_m.gguf'),
        f('llava-q8_0.gguf'),
        f('mmproj-model-f16.gguf', size: 500),
      ]);

      expect(variants.map((v) => v.name),
          <String>['llava-q4_k_m', 'llava-q8_0']);
      for (final v in variants) {
        expect(v.companions.single.name, 'mmproj-model-f16.gguf');
        expect(v.allFiles, hasLength(2));
        expect(v.totalSize, 600);
      }
    });

    test('parses quantisation tags and ignores non-GGUF files', () {
      final variants = groupVariants(<RemoteFile>[
        f('qwen2.5-0.5b-instruct-q4_k_m.gguf'),
        f('qwen2.5-0.5b-instruct-iq3_xxs.gguf'),
        f('qwen2.5-0.5b-instruct-fp16.gguf'),
        f('README.md'),
        f('model.safetensors'),
      ]);

      final quants = <String, String?>{
        for (final v in variants) v.name: v.quantization,
      };
      expect(quants['qwen2.5-0.5b-instruct-q4_k_m'], 'Q4_K_M');
      expect(quants['qwen2.5-0.5b-instruct-iq3_xxs'], 'IQ3_XXS');
      expect(variants, hasLength(3));
    });

    test('separate models in one repo stay separate', () {
      final variants = groupVariants(<RemoteFile>[
        f('gemma-2b-q4_k_m.gguf'),
        f('gemma-7b-q4_k_m.gguf'),
      ]);
      expect(variants, hasLength(2));
    });
  });

  group('isShardSetComplete', () {
    test('accepts a full set and a single file', () {
      expect(
        isShardSetComplete(<RemoteFile>[
          f('m-00001-of-00002.gguf'),
          f('m-00002-of-00002.gguf'),
        ]),
        isTrue,
      );
      expect(isShardSetComplete(<RemoteFile>[f('m.gguf')]), isTrue);
    });

    test('rejects a gap or a short set', () {
      expect(
        isShardSetComplete(<RemoteFile>[
          f('m-00001-of-00003.gguf'),
          f('m-00003-of-00003.gguf'),
        ]),
        isFalse,
      );
      expect(isShardSetComplete(<RemoteFile>[]), isFalse);
    });
  });

  group('source listing', () {
    late HttpServer server;
    late Uri base;
    late HttpClient client;

    setUp(() async {
      // Must match production: autoUncompress off, because ranged downloads
      // break if the client silently inflates bodies. That makes inflating the
      // listing the source layer's job, so the test has to use the same config
      // or it would pass while the real thing fails.
      client = ChunkedDownloader.createHttpClient(useEnvironmentProxy: false);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://${server.address.host}:${server.port}');
      server.listen((request) async {
        final response = request.response;
        final String path = request.uri.path;

        // HuggingFace gzips its tree API. The shared client runs with
        // autoUncompress off (ranged downloads depend on it), so the source
        // layer has to inflate this itself.
        void writeJson(Object payload) {
          final List<int> body = utf8.encode(jsonEncode(payload));
          if (path.contains('/tree/')) {
            response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
            response.add(gzip.encode(body));
          } else {
            response.add(body);
          }
        }

        if (path.contains('/Missing/')) {
          if (path.contains('/repo/files')) {
            // ModelScope signals a missing repo with 200 + a Code field.
            writeJson(<String, Object?>{
              'Code': 404,
              'Message': 'not found',
            });
          } else {
            response.statusCode = HttpStatus.notFound;
          }
          await response.close();
          return;
        }

        if (path.startsWith('/api/models/') && path.contains('/tree/')) {
          writeJson(<Object>[
            <String, Object?>{
              'type': 'file',
              'oid': 'a' * 40, // git SHA-1, must be ignored
              'size': 4856,
              'path': 'README.md',
            },
            <String, Object?>{
              'type': 'file',
              'oid': 'b' * 40,
              'size': 491400032,
              'lfs': <String, Object?>{'oid': 'c' * 64, 'size': 491400032},
              'path': 'model-q4_k_m.gguf',
            },
            <String, Object?>{'type': 'directory', 'path': 'nested'},
          ]);
          await response.close();
          return;
        }

        if (path.contains('/repo/files')) {
          writeJson(<String, Object?>{
            'Code': 200,
            'Data': <String, Object?>{
              'Files': <Object>[
                <String, Object?>{
                  'Path': 'README.md',
                  'Name': 'README.md',
                  'Size': 4856,
                  'Sha256': 'd' * 64,
                  'IsLFS': false,
                  'Type': 'blob',
                },
                <String, Object?>{
                  'Path': 'model-q4_k_m.gguf',
                  'Name': 'model-q4_k_m.gguf',
                  'Size': 491400032,
                  'Sha256': 'c' * 64,
                  'IsLFS': true,
                  'Type': 'blob',
                },
                <String, Object?>{'Path': 'nested', 'Type': 'tree'},
              ],
            },
          });
          await response.close();
          return;
        }

        response.statusCode = HttpStatus.notFound;
        await response.close();
      });
    });

    tearDown(() {
      client.close(force: true);
      return server.close(force: true);
    });

    test('HuggingFace uses lfs.oid as the digest and never the git oid', () async {
      final source = HuggingFaceSource(endpoint: base, client: client);
      final listing = await source.listFiles(const ModelRef('Qwen', 'Demo'));

      expect(listing.sourceId, 'huggingface');
      expect(listing.revision, 'main');
      expect(listing.files, hasLength(2)); // directory entry dropped

      final readme = listing.fileAt('README.md')!;
      expect(readme.sha256, isNull, reason: 'git SHA-1 must not be used');

      final gguf = listing.fileAt('model-q4_k_m.gguf')!;
      expect(gguf.sha256, 'c' * 64);
      expect(gguf.size, 491400032);
      expect(gguf.isLfs, isTrue);
    });

    test('ModelScope exposes digests for plain blobs too', () async {
      final source = ModelScopeSource(endpoint: base, client: client);
      final listing = await source.listFiles(const ModelRef('Qwen', 'Demo'));

      expect(listing.sourceId, 'modelscope');
      expect(listing.revision, 'master');
      expect(listing.files, hasLength(2));
      expect(listing.fileAt('README.md')!.sha256, 'd' * 64);
      expect(listing.fileAt('model-q4_k_m.gguf')!.sha256, 'c' * 64);
    });

    test('both sources agree on the GGUF digest', () async {
      final hf = await HuggingFaceSource(endpoint: base, client: client)
          .listFiles(const ModelRef('Qwen', 'Demo'));
      final ms = await ModelScopeSource(endpoint: base, client: client)
          .listFiles(const ModelRef('Qwen', 'Demo'));

      expect(
        hf.fileAt('model-q4_k_m.gguf')!.sha256,
        ms.fileAt('model-q4_k_m.gguf')!.sha256,
        reason: 'a shared digest is what makes source failover safe',
      );
    });

    test('a missing repo raises ModelNotFoundException on both sources', () async {
      await expectLater(
        HuggingFaceSource(endpoint: base, client: client).listFiles(const ModelRef('Missing', 'X')),
        throwsA(isA<ModelNotFoundException>()),
      );
      await expectLater(
        ModelScopeSource(endpoint: base, client: client).listFiles(const ModelRef('Missing', 'X')),
        throwsA(isA<ModelNotFoundException>()),
      );
    });

    test('download URLs follow each hub convention', () {
      expect(
        HuggingFaceSource(endpoint: Uri.parse('https://hf-mirror.com'))
            .downloadUri(const ModelRef('Qwen', 'Demo'), 'model-q4_k_m.gguf')
            .toString(),
        'https://hf-mirror.com/Qwen/Demo/resolve/main/model-q4_k_m.gguf',
      );

      final ms = ModelScopeSource()
          .downloadUri(const ModelRef('Qwen', 'Demo'), 'model-q4_k_m.gguf');
      expect(ms.path, '/api/v1/models/Qwen/Demo/repo');
      expect(ms.queryParameters['FilePath'], 'model-q4_k_m.gguf');
      expect(ms.queryParameters['Revision'], 'master');
    });
  });

  group('groupVariants (safetensors / MLX)', () {
    List<RemoteFile> mlxRepo() => <RemoteFile>[
          f('model-00001-of-00003.safetensors', size: 5000),
          f('model-00003-of-00003.safetensors', size: 3000),
          f('model-00002-of-00003.safetensors', size: 5000),
          f('model.safetensors.index.json', size: 200),
          f('config.json', size: 5),
          f('tokenizer.json', size: 190),
          f('tokenizer_config.json', size: 10),
          f('chat_template.jinja', size: 8),
          f('.gitattributes', size: 1),
          f('configuration.json', size: 2),
        ];

    test('treats the whole repository as one variant', () {
      final variants = groupVariants(mlxRepo(), repoName: 'Qwen3.8-27B-MLX-8bit');
      expect(variants, hasLength(1));
      expect(variants.single.format, ModelFormat.safetensors);
      expect(variants.single.name, 'Qwen3.8-27B-MLX-8bit');
    });

    test('orders weight shards and carries every support file', () {
      final v = groupVariants(mlxRepo(), repoName: 'Repo').single;

      expect(v.parts.map((p) => p.name), <String>[
        'model-00001-of-00003.safetensors',
        'model-00002-of-00003.safetensors',
        'model-00003-of-00003.safetensors',
      ]);
      // Without config/tokenizer/index the directory looks complete and will
      // not load, so they are part of the variant, not optional extras.
      expect(
        v.companions.map((c) => c.name),
        containsAll(<String>[
          'chat_template.jinja',
          'config.json',
          'model.safetensors.index.json',
          'tokenizer.json',
          'tokenizer_config.json',
        ]),
      );
    });

    test('drops repository plumbing that no tool reads', () {
      final v = groupVariants(mlxRepo(), repoName: 'Repo').single;
      final names = v.allFiles.map((file) => file.name).toSet();
      expect(names, isNot(contains('.gitattributes')));
      expect(names, isNot(contains('configuration.json')));
    });

    test('a GGUF repo is never treated as safetensors', () {
      final variants = groupVariants(<RemoteFile>[
        f('model-q4_k_m.gguf'),
        f('config.json'),
      ], repoName: 'Repo');
      expect(variants.single.format, ModelFormat.gguf);
      expect(variants.single.allFiles.map((file) => file.name),
          <String>['model-q4_k_m.gguf']);
    });

    test('a repo with no weights yields nothing', () {
      expect(groupVariants(<RemoteFile>[f('README.md')]), isEmpty);
    });
  });

  group('isShardSetComplete (safetensors)', () {
    test('accepts a full safetensors set', () {
      expect(
        isShardSetComplete(<RemoteFile>[
          f('model-00001-of-00002.safetensors'),
          f('model-00002-of-00002.safetensors'),
        ]),
        isTrue,
      );
    });

    test('rejects a short safetensors set', () {
      expect(
        isShardSetComplete(<RemoteFile>[
          f('model-00001-of-00006.safetensors'),
          f('model-00002-of-00006.safetensors'),
        ]),
        isFalse,
      );
    });
  });


  group('safetensors with auxiliary weights', () {
    // The shape of PocketAiHub/Qwen3.8-27B-Abliterated-MTPLX-Optimized-Speed:
    // a properly sharded main model beside a vision tower and an MTP head.
    List<RemoteFile> mtpRepo() => <RemoteFile>[
          f('model-00001-of-00004.safetensors', size: 5106),
          f('model-00002-of-00004.safetensors', size: 5079),
          f('model-00003-of-00004.safetensors', size: 5113),
          f('model-00004-of-00004.safetensors', size: 3317),
          f('model-vision.safetensors', size: 878),
          f('mtp.safetensors', size: 810),
          f('model.safetensors.index.json', size: 1),
          f('config.json', size: 1),
          f('tokenizer.json', size: 19),
        ];

    test('counts only the real shards as parts', () {
      final v = groupVariants(mtpRepo(), repoName: 'Repo').single;

      expect(v.parts, hasLength(4));
      expect(v.parts.map((p) => p.name), <String>[
        'model-00001-of-00004.safetensors',
        'model-00002-of-00004.safetensors',
        'model-00003-of-00004.safetensors',
        'model-00004-of-00004.safetensors',
      ]);
    });

    test('keeps the auxiliary weights as companions, not shards', () {
      final v = groupVariants(mtpRepo(), repoName: 'Repo').single;

      expect(
        v.companions.map((c) => c.name),
        containsAll(<String>['model-vision.safetensors', 'mtp.safetensors']),
      );
      // Still downloaded — the model will not load without them.
      expect(v.allFiles, hasLength(9));
    });

    test('the shard set reads as complete', () {
      final v = groupVariants(mtpRepo(), repoName: 'Repo').single;
      expect(isShardSetComplete(v.parts), isTrue);
    });

    test('picks the largest weight set when several are sharded', () {
      final v = groupVariants(<RemoteFile>[
        f('model-00001-of-00002.safetensors', size: 5000),
        f('model-00002-of-00002.safetensors', size: 5000),
        f('draft-00001-of-00002.safetensors', size: 100),
        f('draft-00002-of-00002.safetensors', size: 100),
        f('config.json', size: 1),
      ], repoName: 'Repo').single;

      expect(v.parts.map((p) => p.name),
          everyElement(startsWith('model-')));
      expect(v.companions.map((c) => c.name),
          containsAll(<String>[
            'draft-00001-of-00002.safetensors',
            'draft-00002-of-00002.safetensors',
          ]));
    });
  });

  group('isShardSetComplete tolerance', () {
    test('ignores files that are not shards at all', () {
      expect(
        isShardSetComplete(<RemoteFile>[
          f('model-00001-of-00002.safetensors'),
          f('model-00002-of-00002.safetensors'),
          f('model-vision.safetensors'),
        ]),
        isTrue,
        reason: 'a standalone weight has no set to be missing from',
      );
    });

    test('a list with no shards at all is complete', () {
      expect(isShardSetComplete(<RemoteFile>[f('model.safetensors')]), isTrue);
      expect(
        isShardSetComplete(<RemoteFile>[
          f('a.safetensors'),
          f('b.safetensors'),
        ]),
        isTrue,
      );
    });

    test('still catches a genuinely missing shard', () {
      expect(
        isShardSetComplete(<RemoteFile>[
          f('model-00001-of-00003.safetensors'),
          f('model-00003-of-00003.safetensors'),
          f('model-vision.safetensors'),
        ]),
        isFalse,
      );
    });

    test('still catches shards from mismatched sets', () {
      expect(
        isShardSetComplete(<RemoteFile>[
          f('model-00001-of-00002.safetensors'),
          f('model-00002-of-00004.safetensors'),
        ]),
        isFalse,
      );
    });
  });

}
