/// A repository on a model hub, as `{author}/{repo}`.
///
/// The two halves are kept apart rather than stored as one string because
/// LM Studio's on-disk layout is `models/{author}/{repo}/{file}` — getting that
/// split wrong is the difference between a model showing up and not.
class ModelRef {
  const ModelRef(this.author, this.repo);

  final String author;
  final String repo;

  String get id => '$author/$repo';

  /// Parses `Qwen/Qwen2.5-7B-Instruct-GGUF`, tolerating a full hub URL.
  ///
  /// Throws [FormatException] when there is no `author/repo` to be found.
  factory ModelRef.parse(String input) {
    var text = input.trim();

    if (text.startsWith('http://') || text.startsWith('https://')) {
      final Uri uri = Uri.parse(text);
      final segments = List<String>.of(uri.pathSegments)
        ..removeWhere((s) => s.isEmpty);
      // Drop hub prefixes: /models/{author}/{repo} on ModelScope.
      if (segments.isNotEmpty && segments.first == 'models') {
        segments.removeAt(0);
      }
      // Drop everything from the tree/blob/resolve marker onwards.
      final int marker = segments.indexWhere(
        (s) => s == 'tree' || s == 'blob' || s == 'resolve' || s == 'files',
      );
      if (marker >= 0) segments.removeRange(marker, segments.length);
      if (segments.length < 2) {
        throw FormatException('cannot read author/repo from URL', input);
      }
      text = '${segments[0]}/${segments[1]}';
    }

    final parts = text.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length != 2) {
      throw FormatException(
        'expected "author/repo", got "$input"',
        input,
      );
    }
    return ModelRef(parts[0], parts[1]);
  }

  @override
  bool operator ==(Object other) =>
      other is ModelRef && other.author == author && other.repo == repo;

  @override
  int get hashCode => Object.hash(author, repo);

  @override
  String toString() => id;
}
