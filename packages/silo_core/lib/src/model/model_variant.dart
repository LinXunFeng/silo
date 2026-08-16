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
  final parts = List<RemoteFile>.of(weights)
    ..sort((a, b) => _shardIndex(a.name).compareTo(_shardIndex(b.name)));

  // Everything that is not a weight shard travels with them. These are the
  // config, tokenizer and index files, and the model does not load without
  // them — so unlike GGUF, they are part of the variant rather than optional.
  final companions = all.where((f) => !f.isSafetensors).toList()
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
  final match = _shardPattern.firstMatch(files.first.name);
  if (match == null) return files.length == 1;

  final int expected = int.parse(match.namedGroup('total')!);
  if (files.length != expected) return false;

  final seen = <int>{};
  for (final f in files) {
    final m = _shardPattern.firstMatch(f.name);
    if (m == null) return false;
    if (int.parse(m.namedGroup('total')!) != expected) return false;
    seen.add(int.parse(m.namedGroup('index')!));
  }
  for (var i = 1; i <= expected; i++) {
    if (!seen.contains(i)) return false;
  }
  return true;
}
