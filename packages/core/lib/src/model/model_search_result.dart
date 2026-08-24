import 'model_ref.dart';

/// One repository matched by a keyword search.
class ModelSearchResult {
  const ModelSearchResult({
    required this.ref,
    required this.sourceId,
    this.downloads = 0,
    this.likes = 0,
    this.tags = const <String>[],
    this.description,
  });

  final ModelRef ref;

  /// Which source found it. The same repository often exists on several.
  final String sourceId;

  final int downloads;
  final int likes;

  /// Hub tags, used to tell a GGUF repo from a transformers one.
  final List<String> tags;

  /// A short human label where the hub offers one.
  final String? description;

  /// Weight formats this repository looks likely to hold.
  ///
  /// Inferred rather than fetched: asking every hit for its file list would
  /// turn one search into fifty requests. Wrong occasionally, and cheap.
  Set<String> get formats {
    final formats = <String>{};
    final String haystack = '${ref.repo} ${tags.join(' ')}'.toLowerCase();
    if (haystack.contains('gguf')) formats.add('gguf');
    if (haystack.contains('mlx')) formats.add('mlx');
    if (haystack.contains('safetensors')) formats.add('safetensors');
    return formats;
  }

  /// True when this looks like something a local runner can load directly.
  bool get isLocalReady =>
      formats.contains('gguf') || formats.contains('mlx');

  @override
  String toString() => 'ModelSearchResult(${ref.id} from $sourceId)';
}

/// A repository found on one or more sources, merged.
class MergedSearchResult {
  MergedSearchResult({required this.primary, required this.sourceIds});

  /// The best-populated hit for this repository.
  final ModelSearchResult primary;

  /// Every source that returned it, in the order they were searched.
  final List<String> sourceIds;

  ModelRef get ref => primary.ref;

  int get downloads => primary.downloads;

  Set<String> get formats => primary.formats;

  @override
  String toString() =>
      'MergedSearchResult(${ref.id}, on ${sourceIds.join(', ')})';
}
