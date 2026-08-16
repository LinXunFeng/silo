import 'dart:io';

import '../model/model_ref.dart';
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
