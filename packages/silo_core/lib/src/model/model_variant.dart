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
  });

  /// Variant key, e.g. `qwen2.5-7b-instruct-q4_k_m`, or the repository name for
  /// a safetensors model.
  final String name;

  final ModelFormat format;

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

  // Everything else travels with them: the auxiliary weights above, plus the
  // config, tokenizer and index files. Unlike a GGUF projector these are not
  // optional — the directory does not load without them.
  final companions = all.where((f) => !partPaths.contains(f.path)).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  return <ModelVariant>[
    ModelVariant(
      name: repoName ?? _variantKey(parts.first.name),
      format: ModelFormat.safetensors,
      quantization: _quantizationOf(repoName ?? ''),
      parts: parts,
      companions: companions,
    ),
  ];
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
