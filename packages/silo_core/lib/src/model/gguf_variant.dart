import 'remote_file.dart';

/// A single downloadable choice within a GGUF repository.
///
/// One repository usually holds the same model at a dozen quantisation levels,
/// and a large model is split across shards. The unit a user picks is a
/// *variant* — `q4_k_m` — not a file, and picking it must pull every shard plus
/// any multimodal projector, or the model will not load.
class GgufVariant {
  GgufVariant({
    required this.name,
    required this.quantization,
    required this.parts,
    required this.companions,
  });

  /// Variant key, e.g. `qwen2.5-7b-instruct-q4_k_m`.
  final String name;

  /// The quantisation tag parsed out of the name, e.g. `Q4_K_M`, or null when
  /// the filename does not follow the convention.
  final String? quantization;

  /// Shards in order. A single-file variant has exactly one entry.
  final List<RemoteFile> parts;

  /// Files that must accompany the shards — currently `mmproj-*.gguf`.
  final List<RemoteFile> companions;

  bool get isSharded => parts.length > 1;

  /// Everything that has to be downloaded for this variant to be usable.
  List<RemoteFile> get allFiles => <RemoteFile>[...parts, ...companions];

  int get totalSize => allFiles.fold<int>(0, (a, f) => a + f.size);

  int get partsSize => parts.fold<int>(0, (a, f) => a + f.size);

  @override
  String toString() => 'GgufVariant($name, ${parts.length} part(s), '
      '${companions.length} companion(s), $totalSize bytes)';
}

/// `model-00001-of-00003.gguf` — the shard convention used across hubs.
final RegExp _shardPattern = RegExp(
  r'^(?<stem>.+?)-(?<index>\d{5})-of-(?<total>\d{5})\.gguf$',
  caseSensitive: false,
);

/// Trailing quantisation tag: `-Q4_K_M`, `-IQ3_XXS`, `-f16`, `-BF16`.
final RegExp _quantPattern = RegExp(
  r'-((?:I?Q\d+(?:_[A-Z0-9]+)*)|F16|F32|BF16)$',
  caseSensitive: false,
);

/// Groups a repository's files into the variants a user can actually choose.
///
/// Shards are collapsed into one entry and ordered by index, and every
/// `mmproj-*.gguf` in the repository is attached to every variant, because the
/// projector is shared across quantisations and omitting it is a silent
/// failure at load time.
List<GgufVariant> groupGgufVariants(List<RemoteFile> files) {
  final companions = <RemoteFile>[];
  final grouped = <String, List<RemoteFile>>{};

  for (final file in files) {
    if (!file.isGguf) continue;
    if (file.isMultimodalProjector) {
      companions.add(file);
      continue;
    }
    grouped.putIfAbsent(_variantKey(file.name), () => <RemoteFile>[]).add(file);
  }

  final variants = <GgufVariant>[];
  grouped.forEach((key, parts) {
    parts.sort((a, b) => _shardIndex(a.name).compareTo(_shardIndex(b.name)));
    variants.add(GgufVariant(
      name: key,
      quantization: _quantizationOf(key),
      parts: parts,
      companions: List<RemoteFile>.unmodifiable(companions),
    ));
  });

  variants.sort((a, b) => a.name.compareTo(b.name));
  return variants;
}

/// Strips the shard suffix so all shards of one model share a key.
String _variantKey(String fileName) {
  final match = _shardPattern.firstMatch(fileName);
  if (match != null) return match.namedGroup('stem')!;
  return fileName.toLowerCase().endsWith('.gguf')
      ? fileName.substring(0, fileName.length - 5)
      : fileName;
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
