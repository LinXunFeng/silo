import 'dart:convert';
import 'dart:io';

import '../model/model_ref.dart';

/// One file belonging to a catalogued variant.
class CatalogFile {
  const CatalogFile({
    required this.name,
    required this.sha256,
    required this.size,
  });

  /// File name as the source published it.
  final String name;

  final String sha256;
  final int size;

  Map<String, Object?> toJson() =>
      <String, Object?>{'name': name, 'sha256': sha256, 'size': size};

  static CatalogFile? fromJson(Map<String, Object?> json) {
    final Object? name = json['name'];
    final Object? sha256 = json['sha256'];
    final Object? size = json['size'];
    if (name is! String || sha256 is! String || size is! int) return null;
    return CatalogFile(name: name, sha256: sha256, size: size);
  }
}

/// A model variant held in the store.
class CatalogEntry {
  CatalogEntry({
    required this.ref,
    required this.variant,
    required this.sourceId,
    required this.revision,
    required this.addedAt,
    required this.files,
  });

  final ModelRef ref;

  /// Variant name, e.g. `qwen2.5-0.5b-instruct-q4_k_m`.
  final String variant;

  /// Which source the bytes came from, for provenance.
  final String sourceId;

  final String revision;
  final DateTime addedAt;
  final List<CatalogFile> files;

  /// Stable identity of a variant within the library.
  String get key => '${ref.id}#$variant';

  int get totalSize => files.fold<int>(0, (a, f) => a + f.size);

  Map<String, Object?> toJson() => <String, Object?>{
        'ref': ref.id,
        'variant': variant,
        'source': sourceId,
        'revision': revision,
        'addedAt': addedAt.toIso8601String(),
        'files': files.map((f) => f.toJson()).toList(),
      };

  static CatalogEntry? fromJson(Map<String, Object?> json) {
    final Object? ref = json['ref'];
    final Object? variant = json['variant'];
    final Object? files = json['files'];
    if (ref is! String || variant is! String || files is! List) return null;

    final parsed = <CatalogFile>[];
    for (final Object? f in files) {
      if (f is! Map<String, Object?>) continue;
      final CatalogFile? file = CatalogFile.fromJson(f);
      if (file != null) parsed.add(file);
    }

    return CatalogEntry(
      ref: ModelRef.parse(ref),
      variant: variant,
      sourceId: json['source'] as String? ?? 'unknown',
      revision: json['revision'] as String? ?? 'main',
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      files: parsed,
    );
  }
}

/// A file this library placed inside a target's directory.
class LinkRecord {
  const LinkRecord({
    required this.entryKey,
    required this.targetId,
    required this.sha256,
    required this.path,
    required this.hardLinked,
  });

  final String entryKey;
  final String targetId;
  final String sha256;
  final String path;
  final bool hardLinked;

  Map<String, Object?> toJson() => <String, Object?>{
        'entry': entryKey,
        'target': targetId,
        'sha256': sha256,
        'path': path,
        'hardLinked': hardLinked,
      };

  static LinkRecord? fromJson(Map<String, Object?> json) {
    final Object? entry = json['entry'];
    final Object? target = json['target'];
    final Object? sha256 = json['sha256'];
    final Object? path = json['path'];
    if (entry is! String ||
        target is! String ||
        sha256 is! String ||
        path is! String) {
      return null;
    }
    return LinkRecord(
      entryKey: entry,
      targetId: target,
      sha256: sha256,
      path: path,
      hardLinked: json['hardLinked'] == true,
    );
  }
}

/// The library's record of what it holds and where it has been linked.
///
/// Kept as one small JSON document rather than a database: the whole point of
/// the store is that the blobs are the source of truth, and this file can be
/// rebuilt by re-listing them if it is ever lost.
class Catalog {
  Catalog({List<CatalogEntry>? entries, List<LinkRecord>? links})
      : entries = entries ?? <CatalogEntry>[],
        links = links ?? <LinkRecord>[];

  static const int formatVersion = 1;

  final List<CatalogEntry> entries;
  final List<LinkRecord> links;

  CatalogEntry? find(ModelRef ref, String variant) {
    for (final e in entries) {
      if (e.ref == ref && e.variant == variant) return e;
    }
    return null;
  }

  List<CatalogEntry> forModel(ModelRef ref) =>
      entries.where((e) => e.ref == ref).toList();

  List<LinkRecord> linksFor(String entryKey) =>
      links.where((l) => l.entryKey == entryKey).toList();

  void upsert(CatalogEntry entry) {
    entries.removeWhere((e) => e.key == entry.key);
    entries.add(entry);
  }

  void remove(String entryKey) {
    entries.removeWhere((e) => e.key == entryKey);
    links.removeWhere((l) => l.entryKey == entryKey);
  }

  /// Forgets link records for [entryKey], optionally only for some targets.
  void dropLinks(String entryKey, {Set<String>? targetIds}) {
    links.removeWhere((l) =>
        l.entryKey == entryKey &&
        (targetIds == null || targetIds.contains(l.targetId)));
  }

  void recordLinks(Iterable<LinkRecord> records) {
    for (final record in records) {
      links.removeWhere(
        (l) => l.targetId == record.targetId && l.path == record.path,
      );
      links.add(record);
    }
  }

  /// Digests referenced by at least one catalogued variant.
  Set<String> referencedBlobs() => <String>{
        for (final entry in entries)
          for (final file in entry.files) file.sha256,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'version': formatVersion,
        'entries': entries.map((e) => e.toJson()).toList(),
        'links': links.map((l) => l.toJson()).toList(),
      };

  static Catalog fromJson(Map<String, Object?> json) {
    final entries = <CatalogEntry>[];
    final links = <LinkRecord>[];

    final Object? rawEntries = json['entries'];
    if (rawEntries is List) {
      for (final Object? e in rawEntries) {
        if (e is! Map<String, Object?>) continue;
        final CatalogEntry? entry = CatalogEntry.fromJson(e);
        if (entry != null) entries.add(entry);
      }
    }

    final Object? rawLinks = json['links'];
    if (rawLinks is List) {
      for (final Object? l in rawLinks) {
        if (l is! Map<String, Object?>) continue;
        final LinkRecord? link = LinkRecord.fromJson(l);
        if (link != null) links.add(link);
      }
    }

    return Catalog(entries: entries, links: links);
  }

  /// Reads the catalog, returning an empty one when absent or unreadable.
  static Future<Catalog> read(File file) async {
    try {
      if (!await file.exists()) return Catalog();
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return Catalog();
      if (decoded['version'] != formatVersion) return Catalog();
      return Catalog.fromJson(decoded);
    } on FormatException {
      return Catalog();
    } on FileSystemException {
      return Catalog();
    }
  }

  /// Writes atomically, so an interrupted save cannot lose the library index.
  Future<void> write(File file) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
