import '../download/download_types.dart';
import '../model/model_ref.dart';
import '../model/model_search_result.dart';
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

  /// ModelScope's search is a `PUT` with a JSON body, not a query string, and
  /// the hits arrive under `Data.Model.Models` with the author in `Path` and
  /// the repository in `Name`.
  @override
  Future<List<ModelSearchResult>> search(
    String query, {
    int limit = 25,
    bool localFormatsOnly = false,
  }) async {
    final Uri uri = endpoint.replace(path: '/api/v1/dolphin/models');
    final Object? json = await sendJson(
      uri,
      method: 'PUT',
      body: <String, Object?>{
        'Name': query,
        // No tag filter here, so ask for more and let the caller sift by name.
        'PageSize': localFormatsOnly ? limit * 3 : limit,
        'PageNumber': 1,
        'SortBy': 'Default',
        'Target': '',
        'SingleCriterion': <Object>[],
      },
    );
    if (json is! Map) return const <ModelSearchResult>[];

    final Object? code = json['Code'];
    if (code is int && code != 200) return const <ModelSearchResult>[];

    final Object? data = json['Data'];
    final Object? model = data is Map ? data['Model'] : null;
    final Object? models = model is Map ? model['Models'] : null;
    if (models is! List) return const <ModelSearchResult>[];

    final results = <ModelSearchResult>[];
    for (final Object? entry in models) {
      if (entry is! Map) continue;
      final Object? author = entry['Path'];
      final Object? repo = entry['Name'];
      if (author is! String || repo is! String) continue;
      if (author.isEmpty || repo.isEmpty) continue;

      final String? chinese = entry['ChineseName'] as String?;
      results.add(ModelSearchResult(
        ref: ModelRef(author, repo),
        sourceId: id,
        downloads: entry['Downloads'] is int ? entry['Downloads']! as int : 0,
        likes: entry['Stars'] is int ? entry['Stars']! as int : 0,
        description: (chinese == null || chinese.isEmpty) ? null : chinese,
      ));
    }
    return results;
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
