import 'dart:convert';
import 'dart:io';

import '../model/model_ref.dart';
import '../store/blob_store.dart';
import 'download_target.dart';

/// LM Studio.
///
/// The layout is not negotiable: LM Studio scans
/// `~/.lmstudio/models/{author}/{repo}/{file}` and indexes nothing that sits at
/// a different depth. One level too few or too many and the model simply does
/// not appear, with no error to explain why — which is the single most common
/// way a manual download fails.
class LmStudioTarget extends DownloadTarget {
  LmStudioTarget({Directory? root}) : _root = root;

  final Directory? _root;

  @override
  String get id => 'lmstudio';

  @override
  String get displayName => 'LM Studio';

  @override
  Directory get root => _root ?? Directory(defaultRootPath);

  static String get defaultRootPath {
    final String? home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw StateError('cannot determine home directory');
    }
    return '$home/.lmstudio/models';
  }

  /// LM Studio is considered present when its own directory exists, not just
  /// the models folder Silo might have created itself.
  @override
  Future<bool> isPresent() async {
    if (_root != null) return _root.exists();
    return root.parent.exists();
  }

  @override
  String relativePathFor(ModelRef ref, String fileName) {
    // Flatten any nested repo path: LM Studio wants the file directly under
    // {author}/{repo}, not at whatever depth the hub happened to store it.
    final int slash = fileName.lastIndexOf('/');
    final String leaf = slash < 0 ? fileName : fileName.substring(slash + 1);
    return '${ref.author}/${ref.repo}/$leaf';
  }

  /// Drops weight files the model's own index does not claim.
  ///
  /// LM Studio's MLX backend loads every `*.safetensors` in the directory and
  /// merges them, ignoring `model.safetensors.index.json` — it special-cases
  /// exactly one name, `consolidated.safetensors`. So a repository that ships
  /// an extra weight artifact for a custom runtime (an MTP head, a draft model)
  /// makes the whole model fail to load with "Received N parameters not in
  /// model", even though every byte is correct.
  ///
  /// The index is the model's own statement of what it is made of. Anything
  /// with a `.safetensors` name that it does not list is not part of this
  /// model, so it does not go in the directory — it stays in the store, where
  /// nothing reads it by accident.
  ///
  /// Repositories without an index are left alone: with no manifest there is
  /// nothing to check against, and guessing would be worse than doing nothing.
  @override
  Future<List<TargetFile>> selectFiles(
    List<TargetFile> files,
    BlobStore store,
  ) async {
    const indexName = 'model.safetensors.index.json';
    TargetFile? indexFile;
    for (final file in files) {
      if (file.relativePath.endsWith(indexName)) indexFile = file;
    }
    if (indexFile == null) return files;

    final Set<String>? indexed =
        await _indexedWeightFiles(index: indexFile, store: store);
    if (indexed == null) return files;

    return files.where((file) {
      final String name = _leafOf(file.relativePath);
      if (!name.toLowerCase().endsWith('.safetensors')) return true;
      return indexed.contains(name);
    }).toList();
  }

  /// The weight files named by the index, or null when it cannot be read.
  Future<Set<String>?> _indexedWeightFiles({
    required TargetFile index,
    required BlobStore store,
  }) async {
    try {
      final File blob = store.blobFile(index.sha256);
      if (!await blob.exists()) return null;
      final Object? decoded = jsonDecode(await blob.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      final Object? weightMap = decoded['weight_map'];
      if (weightMap is! Map) return null;

      final names = <String>{};
      for (final Object? value in weightMap.values) {
        if (value is String) names.add(_leafOf(value));
      }
      return names.isEmpty ? null : names;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  String _leafOf(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// Scans for models already installed, so Silo can mark them as present
  /// instead of offering to download what is already there.
  Future<List<InstalledModel>> scanInstalled() async {
    final results = <InstalledModel>[];
    if (!await root.exists()) return results;

    await for (final authorEntry in root.list()) {
      if (authorEntry is! Directory) continue;
      final String author = authorEntry.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;

      await for (final repoEntry in authorEntry.list()) {
        if (repoEntry is! Directory) continue;
        final String repo =
            repoEntry.uri.pathSegments.where((s) => s.isNotEmpty).last;

        final files = <File>[];
        await for (final fileEntry in repoEntry.list()) {
          if (fileEntry is File) files.add(fileEntry);
        }
        if (files.isEmpty) continue;

        var total = 0;
        for (final f in files) {
          total += await f.length();
        }
        results.add(InstalledModel(
          ref: ModelRef(author, repo),
          files: files,
          totalSize: total,
        ));
      }
    }
    return results;
  }
}

/// A model found already sitting in a target's directory.
class InstalledModel {
  const InstalledModel({
    required this.ref,
    required this.files,
    required this.totalSize,
  });

  final ModelRef ref;
  final List<File> files;
  final int totalSize;

  @override
  String toString() =>
      'InstalledModel($ref, ${files.length} files, $totalSize bytes)';
}
