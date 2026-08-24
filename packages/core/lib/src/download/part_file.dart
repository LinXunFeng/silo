import 'dart:convert';
import 'dart:io';

/// Resume state written beside a partially downloaded file as `<name>.part.json`.
///
/// The layout is deliberately dumb: chunk *i* covers
/// `[i * chunkSize, min((i + 1) * chunkSize, size))`, and [done] records how
/// many bytes of each chunk are already on disk. That keeps the sidecar to one
/// integer per chunk instead of a list of objects, which matters when a 15 GB
/// model is split into hundreds of pieces and the file is rewritten every
/// second.
class PartFile {
  PartFile({
    required this.url,
    required this.size,
    required this.chunkSize,
    required this.done,
    this.sha256,
    this.etag,
  });

  static const int formatVersion = 1;

  final String url;
  final int size;
  final int chunkSize;
  final List<int> done;
  final String? sha256;
  final String? etag;

  int get chunkCount => done.length;

  int get received => done.fold<int>(0, (a, b) => a + b);

  bool get isComplete {
    for (var i = 0; i < done.length; i++) {
      if (done[i] < chunkLength(i)) return false;
    }
    return true;
  }

  int chunkStart(int index) => index * chunkSize;

  int chunkEnd(int index) {
    final int end = (index + 1) * chunkSize;
    return end > size ? size : end;
  }

  int chunkLength(int index) => chunkEnd(index) - chunkStart(index);

  bool isChunkComplete(int index) => done[index] >= chunkLength(index);

  /// Builds fresh state for a download of [size] bytes.
  factory PartFile.fresh({
    required Uri url,
    required int size,
    required int chunkSize,
    String? sha256,
    String? etag,
  }) {
    final int count = size <= 0 ? 1 : (size + chunkSize - 1) ~/ chunkSize;
    return PartFile(
      url: url.toString(),
      size: size,
      chunkSize: chunkSize,
      done: List<int>.filled(count, 0),
      sha256: sha256,
      etag: etag,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': formatVersion,
        'url': url,
        'size': size,
        'chunkSize': chunkSize,
        'sha256': sha256,
        'etag': etag,
        'done': done,
      };

  static PartFile? fromJson(Map<String, Object?> json) {
    if (json['version'] != formatVersion) return null;
    final Object? size = json['size'];
    final Object? chunkSize = json['chunkSize'];
    final Object? done = json['done'];
    final Object? url = json['url'];
    if (size is! int || chunkSize is! int || url is! String || done is! List) {
      return null;
    }
    final doneInts = <int>[];
    for (final Object? v in done) {
      if (v is! int) return null;
      doneInts.add(v);
    }
    return PartFile(
      url: url,
      size: size,
      chunkSize: chunkSize,
      done: doneInts,
      sha256: json['sha256'] as String?,
      etag: json['etag'] as String?,
    );
  }

  /// Reads sidecar state, returning null when it is missing or unreadable.
  ///
  /// A corrupt sidecar is never fatal — the worst case is re-downloading.
  static Future<PartFile?> read(File sidecar) async {
    try {
      if (!await sidecar.exists()) return null;
      final Object? decoded = jsonDecode(await sidecar.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      return PartFile.fromJson(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Writes sidecar state atomically, so a crash mid-write cannot leave a
  /// half-truncated JSON file that discards a completed download.
  Future<void> write(File sidecar) async {
    final tmp = File('${sidecar.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    await tmp.rename(sidecar.path);
  }

  /// True when this sidecar describes the same download as [other]'s inputs.
  bool matches({required Uri url, required int? size, String? sha256}) {
    if (size != null && size != this.size) return false;
    if (sha256 != null && this.sha256 != null && sha256 != this.sha256) {
      return false;
    }
    // A source switch (hf-mirror -> ModelScope) keeps the same bytes, so the
    // URL alone is not grounds to discard progress as long as size and digest
    // agree. Only fall back to URL identity when neither is known.
    if (size == null && sha256 == null) {
      return url.toString() == this.url;
    }
    return true;
  }
}
