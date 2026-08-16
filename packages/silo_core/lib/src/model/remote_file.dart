import 'model_ref.dart';

/// One file inside a model repository, as the hub describes it.
class RemoteFile {
  const RemoteFile({
    required this.path,
    required this.size,
    this.sha256,
    this.isLfs = false,
  });

  /// Repository-relative path, e.g. `qwen2.5-7b-instruct-q4_k_m.gguf`.
  final String path;

  final int size;

  /// Lowercase hex SHA-256, when the hub publishes one.
  ///
  /// HuggingFace only carries it for LFS entries (`lfs.oid`); plain git blobs
  /// expose a SHA-1 that is useless for content verification. ModelScope
  /// publishes SHA-256 for everything.
  final String? sha256;

  final bool isLfs;

  /// The final path component.
  String get name {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  bool get isGguf => name.toLowerCase().endsWith('.gguf');

  bool get isSafetensors => name.toLowerCase().endsWith('.safetensors');

  /// Multimodal projector weights. A vision model will load but fail to see
  /// anything without these, and users have no way to guess that.
  bool get isMultimodalProjector => name.toLowerCase().startsWith('mmproj');

  @override
  String toString() => 'RemoteFile($path, $size bytes)';
}

/// The result of listing a repository from one source.
class ModelListing {
  const ModelListing({
    required this.ref,
    required this.revision,
    required this.files,
    required this.sourceId,
  });

  final ModelRef ref;
  final String revision;
  final List<RemoteFile> files;

  /// Which [ModelSource] produced this listing.
  final String sourceId;

  RemoteFile? fileAt(String path) {
    for (final f in files) {
      if (f.path == path) return f;
    }
    return null;
  }

  int get totalSize => files.fold<int>(0, (a, f) => a + f.size);

  @override
  String toString() =>
      'ModelListing($ref@$revision from $sourceId, ${files.length} files)';
}
