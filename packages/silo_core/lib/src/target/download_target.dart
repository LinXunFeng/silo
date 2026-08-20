import 'dart:io';

import '../model/model_ref.dart';
import '../store/blob_store.dart';

/// One file a target wants on disk, and where.
class TargetFile {
  const TargetFile({required this.sha256, required this.relativePath});

  final String sha256;

  /// Path relative to the target's root.
  final String relativePath;
}

/// What happened when a variant was installed into a target.
class InstallResult {
  const InstallResult({
    required this.targetId,
    required this.links,
    required this.root,
  });

  final String targetId;
  final List<LinkResult> links;
  final Directory root;

  /// Bytes this installation actually consumed. Zero when every file was
  /// hard-linked, which is the point.
  int get bytesOnDisk => links.fold<int>(0, (a, l) => a + l.bytesOnDisk);

  /// Bytes the tool sees, as if each file were a full copy.
  int get apparentSize => links.fold<int>(0, (a, l) => a + l.size);

  int get hardLinkCount =>
      links.where((l) => l.method != LinkMethod.copy).length;
}

/// A local tool that wants model files laid out its own way.
///
/// Targets are plugins, and each one is only responsible for two things:
/// saying where its root is, and mapping a model file to a path underneath it.
/// Everything about downloading, verifying and deduplicating happens before a
/// target is ever consulted.
abstract class DownloadTarget {
  /// Stable identifier used on the command line, e.g. `lmstudio`.
  String get id;

  /// Human-readable name for the UI.
  String get displayName;

  /// Where this tool keeps its models.
  Directory get root;

  /// Whether the tool appears to be installed. A target that is not present
  /// is offered but not selected by default.
  Future<bool> isPresent() => root.exists();

  /// Path, relative to [root], where [fileName] from [ref] must live.
  String relativePathFor(ModelRef ref, String fileName);

  /// Narrows a variant's files to the ones this tool should actually receive.
  ///
  /// The store keeps everything a repository publishes, because it is a library
  /// and completeness is the point. A target may still need less: a tool can
  /// choke on a file it was never meant to read, and it is the target that
  /// knows which. Defaults to installing everything.
  Future<List<TargetFile>> selectFiles(
    List<TargetFile> files,
    BlobStore store,
  ) async =>
      files;

  /// Puts every file of a variant in place, hard-linking from [store].
  Future<InstallResult> install(
    ModelRef ref,
    List<TargetFile> files,
    BlobStore store, {
    bool overwrite = true,
  }) async {
    final wanted = await selectFiles(files, store);
    final links = <LinkResult>[];
    for (final file in wanted) {
      final String relative = relativePathFor(ref, file.relativePath);
      final destination = File('${root.path}/$relative');
      links.add(await store.linkTo(
        file.sha256,
        destination,
        overwrite: overwrite,
      ));
    }
    return InstallResult(targetId: id, links: links, root: root);
  }

  /// Removes a variant's files from this target. Blobs are untouched — only
  /// `silo gc` deletes those, and only when nothing references them.
  Future<int> uninstall(ModelRef ref, List<TargetFile> files) async {
    var removed = 0;
    for (final file in files) {
      final destination =
          File('${root.path}/${relativePathFor(ref, file.relativePath)}');
      if (await destination.exists()) {
        await destination.delete();
        removed++;
      }
    }
    await _pruneEmptyDirectories(ref);
    return removed;
  }

  Future<void> _pruneEmptyDirectories(ModelRef ref) async {
    var dir = Directory('${root.path}/${relativePathFor(ref, 'x')}').parent;
    while (dir.path.startsWith(root.path) && dir.path != root.path) {
      try {
        if (await dir.list().isEmpty) {
          await dir.delete();
        } else {
          return;
        }
      } on FileSystemException {
        return;
      }
      dir = dir.parent;
    }
  }
}
