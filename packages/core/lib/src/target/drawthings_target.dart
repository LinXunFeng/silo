import 'dart:io';

import '../model/model_ref.dart';
import '../store/blob_store.dart';
import 'download_target.dart';

/// Draw Things.
///
/// Unlike LM Studio, Draw Things does not read weights where they lie. It
/// converts every checkpoint into its own format on import, so the closest a
/// file can be put to it is the list its import dialog offers. That list is
/// read from `Documents/Downloads` inside the app's sandbox container — the
/// top level only, every subdirectory is skipped — so that is the root, and
/// every file goes directly into it.
///
/// The converted model Draw Things writes is a file of its own; the hard link
/// only saves the second copy a manual download would have left behind.
class DrawThingsTarget extends DownloadTarget {
  DrawThingsTarget({Directory? root}) : _root = root;

  final Directory? _root;

  /// Suffixes Draw Things' importer accepts. Anything else in the folder shows
  /// up in the import list as a choice that can only fail.
  ///
  /// `.bin` is accepted by the importer too, but in a hub repository it is
  /// as likely to be `training_args.bin` or a pickled duplicate of the
  /// safetensors weights as a model, so it is left out.
  static const List<String> importableSuffixes = <String>[
    '.safetensors',
    '.ckpt',
    '.pt',
    '.pth',
    '.patch',
  ];

  /// `model-00001-of-00003.safetensors`. The importer takes one file, so a
  /// shard on its own is not a model it can read.
  static final RegExp _shardPattern =
      RegExp(r'-\d{5}-of-\d{5}\.[^.]+$', caseSensitive: false);

  @override
  String get id => 'drawthings';

  @override
  String get displayName => 'Draw Things';

  @override
  Directory get root => _root ?? Directory(defaultRootPath);

  @override
  bool get requiresImport => true;

  /// The app's sandbox container, which macOS creates on its first launch.
  static String get containerPath {
    // A macOS sandbox container, so there is no other platform to fall back
    // for.
    final String? home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('cannot determine home directory');
    }
    return '$home/Library/Containers/com.liuliu.draw-things';
  }

  static String get defaultRootPath =>
      '$containerPath/Data/Documents/Downloads';

  /// Draw Things is considered present when its sandbox container exists —
  /// the app creates it on first launch, and Silo never does.
  @override
  Future<bool> isPresent() async {
    if (_root != null) return _root.exists();
    return Directory(containerPath).exists();
  }

  /// Refuses to link into a container the app has not made.
  ///
  /// Linking creates whatever directories the path needs, and a container
  /// Silo made would be one the sandbox did not: at best Draw Things would
  /// look installed when it is not, at worst the app's own first launch would
  /// trip over it. An overridden root is the user's to create.
  @override
  Future<void> ensureReady() async {
    if (_root == null && !await isPresent()) {
      throw StateError('Draw Things has not been launched on this Mac yet; '
          'open it once so it can create its folder, then link again');
    }
  }

  @override
  String relativePathFor(ModelRef ref, String fileName, {String directory = ''}) {
    // Flat by necessity: the import list never looks below the top level.
    // Every diffusers-style repository ships a `diffusion_pytorch_model
    // .safetensors`, so the leaf alone would have one repository's file
    // silently replace another's. The author and repository go in front, which
    // also tells the user which model they are importing.
    final String leaf = _leafOf(fileName);
    final String folder =
        directory.isEmpty ? '' : '--${directory.replaceAll('/', '--')}';
    return '${ref.author}--${ref.repo}$folder--$leaf';
  }

  /// Keeps only the single-file weights the importer can read.
  ///
  /// Config, tokenizer and README files are what make a directory loadable
  /// elsewhere, but here each would be one more entry in the import list that
  /// fails when picked. Shards are dropped for the same reason: the importer
  /// reads one file, never a set.
  @override
  Future<List<TargetFile>> selectFiles(
    List<TargetFile> files,
    BlobStore store,
  ) async =>
      files.where((file) => isImportable(file.relativePath)).toList();

  /// Whether Draw Things' importer can read [fileName] on its own.
  static bool isImportable(String fileName) {
    final String name = fileName.toLowerCase();
    if (_shardPattern.hasMatch(name)) return false;
    return importableSuffixes.any(name.endsWith);
  }

  /// Files waiting in the import folder, whoever put them there.
  Future<List<File>> scanStaged() async {
    if (!await root.exists()) return const <File>[];
    final files = <File>[];
    await for (final entry in root.list()) {
      if (entry is File && isImportable(entry.path)) files.add(entry);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  String _leafOf(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
