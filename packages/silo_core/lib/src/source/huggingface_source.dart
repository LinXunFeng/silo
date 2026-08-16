import 'dart:io';

import '../download/download_types.dart';
import '../model/model_ref.dart';
import '../model/remote_file.dart';
import 'model_source.dart';

/// HuggingFace, or any endpoint that speaks its API.
///
/// `hf-mirror.com` is API-compatible with `huggingface.co`, so the mirror is
/// not a separate implementation — it is the same source pointed elsewhere.
/// That is the whole reason the endpoint is a constructor argument.
class HuggingFaceSource extends HttpModelSource {
  HuggingFaceSource({
    Uri? endpoint,
    this.id = 'huggingface',
    this.displayName = 'HuggingFace',
    String? token,
    super.client,
  })  : endpoint = endpoint ?? Uri.parse('https://huggingface.co'),
        _token = token;

  /// Preconfigured for the `hf-mirror.com` mirror.
  factory HuggingFaceSource.mirror({HttpClient? client, String? token}) {
    return HuggingFaceSource(
      endpoint: Uri.parse('https://hf-mirror.com'),
      id: 'hf-mirror',
      displayName: 'HF Mirror (hf-mirror.com)',
      client: client,
      token: token,
    );
  }

  final Uri endpoint;
  final String? _token;

  @override
  final String id;

  @override
  final String displayName;

  @override
  String get defaultRevision => 'main';

  @override
  Map<String, String> get headers => _token == null
      ? const <String, String>{}
      : <String, String>{HttpHeaders.authorizationHeader: 'Bearer $_token'};

  @override
  Future<ModelListing> listFiles(ModelRef ref, {String? revision}) async {
    final String rev = revision ?? defaultRevision;
    final Uri uri = endpoint.replace(
      path: '/api/models/${ref.author}/${ref.repo}/tree/$rev',
      queryParameters: <String, String>{'recursive': 'true'},
    );

    final Object? json = await getJson(uri);
    if (json is! List) {
      throw DownloadException('unexpected tree payload', uri: uri);
    }

    final files = <RemoteFile>[];
    for (final Object? entry in json) {
      if (entry is! Map) continue;
      if (entry['type'] != 'file') continue;

      final Object? path = entry['path'];
      if (path is! String) continue;

      // `lfs.oid` is the real SHA-256. The top-level `oid` is a git blob SHA-1
      // and must never be used for content verification.
      final Object? lfs = entry['lfs'];
      String? sha256;
      int? lfsSize;
      if (lfs is Map) {
        final Object? oid = lfs['oid'];
        if (oid is String && _isSha256(oid)) sha256 = oid.toLowerCase();
        final Object? size = lfs['size'];
        if (size is int) lfsSize = size;
      }

      final Object? size = entry['size'];
      files.add(RemoteFile(
        path: path,
        size: lfsSize ?? (size is int ? size : 0),
        sha256: sha256,
        isLfs: lfs is Map,
      ));
    }

    return ModelListing(
      ref: ref,
      revision: rev,
      files: files,
      sourceId: id,
    );
  }

  @override
  Uri downloadUri(ModelRef ref, String path, {String? revision}) {
    final String rev = revision ?? defaultRevision;
    return endpoint.replace(
      path: '/${ref.author}/${ref.repo}/resolve/$rev/$path',
    );
  }
}

bool _isSha256(String value) =>
    RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
