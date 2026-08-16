import 'dart:io';

import '../util/sha256.dart';

/// How a blob was made to appear at a destination path.
enum LinkMethod {
  /// A second directory entry pointing at the same inode. Free, and the tool
  /// reading it cannot tell the difference from a normal file.
  hardLink,

  /// A full byte-for-byte copy. Used when a hard link is impossible — most
  /// often because the destination is on a different volume.
  copy,

  /// The destination already pointed at this blob; nothing was done.
  alreadyLinked,
}

/// The outcome of putting a blob at a destination path.
class LinkResult {
  const LinkResult({
    required this.sha256,
    required this.path,
    required this.method,
    required this.size,
  });

  final String sha256;
  final String path;
  final LinkMethod method;
  final int size;

  /// Bytes of disk this destination actually cost.
  int get bytesOnDisk => method == LinkMethod.copy ? size : 0;

  @override
  String toString() => 'LinkResult(${method.name}, $path)';
}

/// Content-addressed storage for model files.
///
/// This is the whole point of Silo: one physical copy of a given file, no
/// matter how many tools want it. A 7B model installed in LM Studio,
/// llama.cpp and a scratch directory costs 4 GB once, not three times over.
class BlobStore {
  BlobStore(this.root);

  /// Defaults to `~/.silo`.
  factory BlobStore.defaultLocation() => BlobStore(Directory(defaultRootPath));

  final Directory root;

  static String get defaultRootPath {
    final String? home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw StateError('cannot determine home directory');
    }
    return '$home/.silo';
  }

  Directory get blobsDir => Directory('${root.path}/blobs');

  /// Scratch space for in-flight downloads. Deliberately inside [root] so the
  /// finished file can be moved into place with a rename rather than a copy.
  Directory get tempDir => Directory('${root.path}/tmp');

  Future<void> ensureCreated() async {
    await blobsDir.create(recursive: true);
    await tempDir.create(recursive: true);
  }

  /// Where the blob for [sha256] lives.
  ///
  /// Fanned out by the first two hex characters so a large library does not
  /// end up with tens of thousands of entries in one directory.
  File blobFile(String sha256) {
    final String hex = sha256.toLowerCase();
    return File('${blobsDir.path}/${hex.substring(0, 2)}/$hex');
  }

  Future<bool> has(String sha256) => blobFile(sha256).exists();

  /// A scratch path for downloading [sha256] before it is verified.
  ///
  /// No extension: the downloader appends its own `.part.json` sidecar, and
  /// `<sha>.part.part.json` is nobody's idea of a readable filename.
  File stagingFile(String sha256) =>
      File('${tempDir.path}/${sha256.toLowerCase()}');

  /// Moves a verified [staged] file into the store under [sha256].
  ///
  /// If the blob is already present the staged file is simply discarded — that
  /// is deduplication doing its job, and it is not an error.
  ///
  /// Set [verify] to re-hash before ingesting; the downloader has usually done
  /// this already.
  Future<File> ingest(
    File staged,
    String sha256, {
    bool verify = false,
  }) async {
    final String hex = sha256.toLowerCase();
    if (verify) {
      final String actual = await sha256OfFile(staged);
      if (actual != hex) {
        throw ArgumentError(
          'refusing to ingest $staged: hashes to $actual, not $hex',
        );
      }
    }

    final File destination = blobFile(hex);
    if (await destination.exists()) {
      await staged.delete();
      return destination;
    }

    await destination.parent.create(recursive: true);
    try {
      return await staged.rename(destination.path);
    } on FileSystemException {
      // Different volume: copy, then drop the original.
      final File copied = await staged.copy(destination.path);
      await staged.delete();
      return copied;
    }
  }

  /// Makes the blob for [sha256] appear at [destination].
  ///
  /// Prefers a hard link, which costs nothing and is indistinguishable from a
  /// real file to whatever tool reads it. Falls back to a copy when the link
  /// cannot be made — typically a different volume.
  Future<LinkResult> linkTo(
    String sha256,
    File destination, {
    bool overwrite = true,
  }) async {
    final File blob = blobFile(sha256);
    if (!await blob.exists()) {
      throw StateError('blob $sha256 is not in the store');
    }
    final int size = await blob.length();

    if (await destination.exists()) {
      if (await _isSameInode(blob, destination)) {
        return LinkResult(
          sha256: sha256,
          path: destination.path,
          method: LinkMethod.alreadyLinked,
          size: size,
        );
      }
      if (!overwrite) {
        throw FileSystemException('destination exists', destination.path);
      }
      await destination.delete();
    }

    await destination.parent.create(recursive: true);

    if (await _hardLink(blob, destination)) {
      return LinkResult(
        sha256: sha256,
        path: destination.path,
        method: LinkMethod.hardLink,
        size: size,
      );
    }

    await blob.copy(destination.path);
    return LinkResult(
      sha256: sha256,
      path: destination.path,
      method: LinkMethod.copy,
      size: size,
    );
  }

  /// Deletes the blob for [sha256], if present. Returns the bytes reclaimed.
  Future<int> remove(String sha256) async {
    final File blob = blobFile(sha256);
    if (!await blob.exists()) return 0;
    final int size = await blob.length();
    await blob.delete();
    return size;
  }

  /// Every SHA-256 currently in the store.
  Future<List<String>> listBlobs() async {
    if (!await blobsDir.exists()) return <String>[];
    final results = <String>[];
    await for (final entity in blobsDir.list(recursive: true)) {
      if (entity is! File) continue;
      final String name = entity.uri.pathSegments.last;
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(name)) results.add(name);
    }
    results.sort();
    return results;
  }

  /// Total bytes physically held by the store.
  Future<int> totalSize() async {
    if (!await blobsDir.exists()) return 0;
    var total = 0;
    await for (final entity in blobsDir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Removes staged files left behind by an interrupted run.
  Future<int> pruneStaging() async {
    if (!await tempDir.exists()) return 0;
    var reclaimed = 0;
    await for (final entity in tempDir.list()) {
      if (entity is! File) continue;
      reclaimed += await entity.length();
      await entity.delete();
    }
    return reclaimed;
  }
}

/// Creates a hard link, returning false when the platform or filesystem
/// refuses.
///
/// `dart:io` only models symlinks — [Link] is `symlink(2)`, and a symlink is
/// the wrong tool here because tools that resolve and copy paths, or that run
/// with a different working directory, can break on it. So this shells out to
/// `ln`, which is present on every macOS and Linux box, and lets the caller
/// fall back to copying when it fails.
Future<bool> _hardLink(File source, File destination) async {
  if (!Platform.isMacOS && !Platform.isLinux) return false;
  try {
    final result = await Process.run(
      '/bin/ln',
      <String>[source.absolute.path, destination.absolute.path],
    );
    if (result.exitCode != 0) return false;
    return destination.existsSync();
  } on ProcessException {
    return false;
  }
}

/// True when both paths resolve to the same inode — i.e. already hard-linked.
Future<bool> _isSameInode(File a, File b) async {
  final String? idA = await inodeIdOf(a.path);
  if (idA == null) return false;
  return idA == await inodeIdOf(b.path);
}

/// `device:inode` for [path], or null when it cannot be determined.
///
/// `dart:io` does not expose `st_ino`, and the identity of two paths is exactly
/// the question a deduplicating store has to answer — so ask `stat(1)`. Callers
/// treat null as "assume different", which is the safe direction.
Future<String?> inodeIdOf(String path) async {
  if (!Platform.isMacOS && !Platform.isLinux) return null;
  final List<String> args = Platform.isMacOS
      ? <String>['-f', '%d:%i', path]
      : <String>['-c', '%d:%i', path];
  for (final String exe in <String>['/usr/bin/stat', '/bin/stat']) {
    if (!File(exe).existsSync()) continue;
    try {
      final result = await Process.run(exe, args);
      if (result.exitCode != 0) return null;
      final String out = (result.stdout as String).trim();
      return out.isEmpty ? null : out;
    } on ProcessException {
      continue;
    }
  }
  return null;
}
