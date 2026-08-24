import 'remote_file.dart';

/// The weight format a repository publishes.
enum ModelFormat {
  /// llama.cpp's single-file format. One repository usually holds the same
  /// model at a dozen quantisation levels, and each is independently usable.
  gguf,

  /// The safetensors layout used by transformers, vLLM and MLX. The weights
  /// are only half of it — without `config.json`, the tokenizer files and the
  /// shard index, the directory will not load.
  safetensors,

  unknown,
}

/// A single downloadable choice within a repository.
///
/// The unit a user picks is a *variant*, not a file. What that means depends on
/// the format: for GGUF it is one quantisation (plus every shard of it, plus
/// any multimodal projector); for safetensors it is the whole repository,
/// because the config and tokenizer files are not optional.
class ModelVariant {
  ModelVariant({
    required this.name,
    required this.format,
    required this.quantization,
    required this.parts,
    required this.companions,
    this.directory = '',
  });

  /// Variant key, e.g. `qwen2.5-7b-instruct-q4_k_m`, or the repository name for
  /// a safetensors model.
  final String name;

  final ModelFormat format;

  /// Repository subdirectory this variant lives in, or empty for the root.
  ///
  /// Safetensors repositories often ship several quantisations as sibling
  /// folders — `2-bit/`, `4-bit/`, `8-bit/`. Each is a whole model; which one
  /// you want is the choice, and merging them would claim the repository is
  /// four times its real size and download all of it.
  final String directory;

  /// The quantisation tag parsed out of the name, e.g. `Q4_K_M`, or null when
  /// the filename does not follow the convention.
  final String? quantization;

  /// Weight shards, in order. A single-file variant has exactly one entry.
  final List<RemoteFile> parts;

  /// Files that must accompany the weights: `mmproj-*.gguf` for a vision GGUF,
  /// or the whole config/tokenizer set for safetensors.
  final List<RemoteFile> companions;

  bool get isSharded => parts.length > 1;

  /// Everything that has to be downloaded for this variant to be usable.
  List<RemoteFile> get allFiles => <RemoteFile>[...parts, ...companions];

  int get totalSize => allFiles.fold<int>(0, (a, f) => a + f.size);

  int get partsSize => parts.fold<int>(0, (a, f) => a + f.size);

  @override
  String toString() => 'ModelVariant($name, ${format.name}, '
      '${parts.length} part(s), ${companions.length} companion(s), '
      '$totalSize bytes)';
}

/// `model-00001-of-00003.gguf` / `model-00001-of-00006.safetensors`.
final RegExp _shardPattern = RegExp(
  r'^(?<stem>.+?)-(?<index>\d{5})-of-(?<total>\d{5})\.(?<ext>gguf|safetensors)$',
  caseSensitive: false,
);

/// Trailing quantisation tag: `-Q4_K_M`, `-IQ3_XXS`, `-f16`, `-BF16`.
final RegExp _quantPattern = RegExp(
  r'-((?:I?Q\d+(?:_[A-Z0-9]+)*)|F16|F32|BF16)$',
  caseSensitive: false,
);

/// Repository plumbing that no tool needs on disk.
const Set<String> _skippedFiles = <String>{
  '.gitattributes',
  '.gitignore',
  // ModelScope adds this to every repository; it means nothing to LM Studio.
  'configuration.json',
};

/// Groups a repository's files into the variants a user can choose.
///
/// GGUF repositories yield one variant per quantisation, with shards collapsed
/// and every `mmproj-*.gguf` attached — the projector is shared across
/// quantisations and omitting it fails silently at load time.
///
/// Safetensors repositories yield exactly one variant covering the whole
/// repository. There is nothing to choose between, and dropping the small
/// files would produce a directory that looks complete and does not load.
List<ModelVariant> groupVariants(List<RemoteFile> files, {String? repoName}) {
  final usable = files.where((f) => !_skippedFiles.contains(f.name)).toList();

  final gguf = usable.where((f) => f.isGguf).toList();
  if (gguf.isNotEmpty) return _groupGguf(gguf);

  final safetensors = usable.where((f) => f.isSafetensors).toList();
  if (safetensors.isNotEmpty) {
    return _groupSafetensors(safetensors, usable, repoName);
  }

  return const <ModelVariant>[];
}

List<ModelVariant> _groupGguf(List<RemoteFile> files) {
  final companions = <RemoteFile>[];
  final grouped = <String, List<RemoteFile>>{};

  for (final file in files) {
    if (file.isMultimodalProjector) {
      companions.add(file);
      continue;
    }
    grouped.putIfAbsent(_variantKey(file.name), () => <RemoteFile>[]).add(file);
  }

  final variants = <ModelVariant>[];
  grouped.forEach((key, parts) {
    parts.sort((a, b) => _shardIndex(a.name).compareTo(_shardIndex(b.name)));
    variants.add(ModelVariant(
      name: key,
      format: ModelFormat.gguf,
      quantization: _quantizationOf(key),
      parts: parts,
      companions: List<RemoteFile>.unmodifiable(companions),
    ));
  });

  variants.sort((a, b) => a.name.compareTo(b.name));
  return variants;
}

List<ModelVariant> _groupSafetensors(
  List<RemoteFile> weights,
  List<RemoteFile> all,
  String? repoName,
) {
  // One variant per directory holding weights. A repository that publishes
  // 2-bit/, 4-bit/ and 8-bit/ side by side is offering three models, not one
  // enormous one.
  final dirs = <String>{for (final file in weights) _directoryOf(file.path)};

  final variants = <ModelVariant>[
    for (final dir in dirs)
      _safetensorsVariantIn(
        directory: dir,
        weights: weights.where((f) => _directoryOf(f.path) == dir).toList(),
        all: all,
        repoName: repoName,
      ),
  ];

  // Root first, then by name, so the plain repository reads before its
  // per-quantisation folders.
  variants.sort((a, b) {
    if (a.directory.isEmpty != b.directory.isEmpty) {
      return a.directory.isEmpty ? -1 : 1;
    }
    return a.name.compareTo(b.name);
  });
  return variants;
}

ModelVariant _safetensorsVariantIn({
  required String directory,
  required List<RemoteFile> weights,
  required List<RemoteFile> all,
  required String? repoName,
}) {
  // A repository can hold weights that are not part of the main tensor set —
  // a vision tower, an MTP head — sitting beside a properly sharded model.
  // They are needed to load it, but they are not shards of it, and treating
  // them as such makes a complete `-of-00004` set look like six broken pieces.
  final sharded = <String, List<RemoteFile>>{};
  final standalone = <RemoteFile>[];
  for (final file in weights) {
    final match = _shardPattern.firstMatch(file.name);
    if (match == null) {
      standalone.add(file);
    } else {
      sharded.putIfAbsent(match.namedGroup('stem')!, () => <RemoteFile>[])
          .add(file);
    }
  }

  // The main model is the biggest weight set; anything else rides along.
  final groups = <List<RemoteFile>>[
    ...sharded.values,
    for (final file in standalone) <RemoteFile>[file],
  ]..sort((a, b) => _totalSize(b).compareTo(_totalSize(a)));

  final parts = List<RemoteFile>.of(groups.first)
    ..sort((a, b) => _shardIndex(a.name).compareTo(_shardIndex(b.name)));
  final partPaths = parts.map((f) => f.path).toSet();

  // Companions come from this directory, falling back to the repository root
  // for anything it does not provide.
  //
  // The folder always wins. A quantisation folder ships its own config.json
  // and shard index, and those describe *that* quantisation — taking the root
  // copy as well would put two files with one name into a flat target
  // directory, and the loader would read whichever landed last.
  final byLeaf = <String, RemoteFile>{};
  for (final file in all) {
    if (partPaths.contains(file.path)) continue;
    final String dir = _directoryOf(file.path);
    final bool own = dir == directory;
    final bool inheritedFromRoot =
        directory.isNotEmpty && dir.isEmpty && !file.isSafetensors;
    if (!own && !inheritedFromRoot) continue;

    final String leaf = file.name;
    if (own || !byLeaf.containsKey(leaf)) {
      // `own` overwrites an inherited entry; inherited never overwrites `own`.
      if (own || _directoryOf(byLeaf[leaf]?.path ?? '') != directory) {
        byLeaf[leaf] = file;
      }
    }
  }
  final companions = byLeaf.values.toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final String base = repoName ?? _variantKey(parts.first.name);
  return ModelVariant(
    name: directory.isEmpty ? base : '$base-$directory',
    format: ModelFormat.safetensors,
    quantization: _quantizationOf(directory.isEmpty ? base : directory),
    parts: parts,
    companions: companions,
    directory: directory,
  );
}

String _directoryOf(String path) {
  final int slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

int _totalSize(List<RemoteFile> files) =>
    files.fold<int>(0, (sum, f) => sum + f.size);

/// Strips the shard suffix so all shards of one model share a key.
String _variantKey(String fileName) {
  final match = _shardPattern.firstMatch(fileName);
  if (match != null) return match.namedGroup('stem')!;
  for (final ext in <String>['.gguf', '.safetensors']) {
    if (fileName.toLowerCase().endsWith(ext)) {
      return fileName.substring(0, fileName.length - ext.length);
    }
  }
  return fileName;
}

int _shardIndex(String fileName) {
  final match = _shardPattern.firstMatch(fileName);
  if (match == null) return 1;
  return int.tryParse(match.namedGroup('index')!) ?? 1;
}

String? _quantizationOf(String variantKey) {
  final match = _quantPattern.firstMatch(variantKey);
  return match?.group(1)?.toUpperCase();
}

/// True when [files] look like a complete shard set (no gaps, right count).
///
/// A partial shard set loads as a corrupt model rather than failing cleanly, so
/// this is checked before anything is handed to a tool.
bool isShardSetComplete(List<RemoteFile> files) {
  if (files.isEmpty) return false;

  // Only shard-named files can be incomplete. Anything else in the list is a
  // whole file in its own right and has no set to be missing from.
  final shards = <RegExpMatch>[];
  for (final file in files) {
    final match = _shardPattern.firstMatch(file.name);
    if (match != null) shards.add(match);
  }
  if (shards.isEmpty) return true;

  final int expected = int.parse(shards.first.namedGroup('total')!);
  final seen = <int>{};
  for (final match in shards) {
    if (int.parse(match.namedGroup('total')!) != expected) return false;
    seen.add(int.parse(match.namedGroup('index')!));
  }
  if (seen.length != expected) return false;
  for (var i = 1; i <= expected; i++) {
    if (!seen.contains(i)) return false;
  }
  return true;
}
