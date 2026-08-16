import '../download/download_types.dart';
import '../model/model_ref.dart';
import '../model/remote_file.dart';
import 'model_source.dart';

/// ModelScope (魔搭), Alibaba's model hub.
///
/// Domestically fast, and it mirrors most popular GGUF repositories under the
/// same `author/repo` id as HuggingFace — which is what makes a same-model,
/// multiple-source race possible at all.
class ModelScopeSource extends HttpModelSource {
  ModelScopeSource({Uri? endpoint, super.client})
      : endpoint = endpoint ?? Uri.parse('https://www.modelscope.cn');

  final Uri endpoint;

  @override
  String get id => 'modelscope';

  @override
  String get displayName => 'ModelScope (魔搭)';

  @override
  String get defaultRevision => 'master';

  @override
  Future<ModelListing> listFiles(ModelRef ref, {String? revision}) async {
    final String rev = revision ?? defaultRevision;
    final Uri uri = endpoint.replace(
      path: '/api/v1/models/${ref.author}/${ref.repo}/repo/files',
      queryParameters: <String, String>{'Revision': rev, 'Recursive': 'True'},
    );

    final Object? json = await getJson(uri);
    if (json is! Map) {
      throw DownloadException('unexpected files payload', uri: uri);
    }

    // ModelScope answers 200 with a non-200 `Code` for a missing repo.
    final Object? code = json['Code'];
    if (code is int && code != 200) {
      if (code == 404 || code == 10010205) throw ModelNotFoundException(uri);
      throw DownloadException(
        'listing failed: ${json['Message'] ?? code}',
        uri: uri,
        statusCode: code,
      );
    }

    final Object? data = json['Data'];
    final Object? rawFiles = data is Map ? data['Files'] : null;
    if (rawFiles is! List) {
      throw DownloadException('unexpected files payload', uri: uri);
    }

    final files = <RemoteFile>[];
    for (final Object? entry in rawFiles) {
      if (entry is! Map) continue;
      if (entry['Type'] == 'tree') continue;

      final Object? path = entry['Path'];
      if (path is! String) continue;

      final Object? sha = entry['Sha256'];
      final Object? size = entry['Size'];
      files.add(RemoteFile(
        path: path,
        size: size is int ? size : 0,
        // ModelScope publishes SHA-256 for plain blobs too, not just LFS.
        sha256: sha is String && _isSha256(sha) ? sha.toLowerCase() : null,
        isLfs: entry['IsLFS'] == true,
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
    return endpoint.replace(
      path: '/api/v1/models/${ref.author}/${ref.repo}/repo',
      queryParameters: <String, String>{
        'FilePath': path,
        'Revision': revision ?? defaultRevision,
      },
    );
  }
}

bool _isSha256(String value) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
