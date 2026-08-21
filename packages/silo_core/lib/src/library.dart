import 'dart:async';
import 'dart:io';

import 'download/chunked_downloader.dart';
import 'download/download_types.dart';
import 'model/model_ref.dart';
import 'model/model_search_result.dart';
import 'model/model_variant.dart';
import 'model/remote_file.dart';
import 'source/model_source.dart';
import 'source/source_race.dart';
import 'store/blob_store.dart';
import 'store/catalog.dart';
import 'target/download_target.dart';
import 'util/sha256.dart';

/// Progress of an `add`, across all of a variant's files.
class AddProgress {
  const AddProgress({
    required this.fileName,
    required this.fileIndex,
    required this.fileCount,
    required this.file,
    required this.completedBytes,
    required this.totalBytes,
    required this.sourceId,
  });

  final String fileName;
  final int fileIndex;
  final int fileCount;

  /// Progress of the file currently transferring.
  final DownloadProgress file;

  /// Bytes finished across files already done.
  final int completedBytes;

  /// Bytes across the whole variant.
  final int totalBytes;

  final String sourceId;

  int get receivedBytes => completedBytes + file.received;

  double get fraction =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

/// Steers a running [SiloLibrary.add].
///
/// An `add` spans many files and therefore many downloads; the caller holds one
/// of these for the whole run rather than a handle per file. Pausing leaves
/// every `.part.json` intact, so the same `add` call resumes where it stopped.
class AddHandle {
  DownloadHandle? _current;
  DownloadOutcome? _stop;

  /// Set when pause or cancel has been requested.
  DownloadOutcome? get stopRequested => _stop;

  bool get isStopping => _stop != null;

  /// Stops after in-flight buffers land, keeping partial data resumable.
  void pause() => _request(DownloadOutcome.paused);

  /// Stops and discards the file currently transferring. Files already
  /// ingested into the store stay there — they are complete and verified.
  void cancel() => _request(DownloadOutcome.cancelled);

  void _request(DownloadOutcome outcome) {
    _stop ??= outcome;
    final handle = _current;
    if (handle == null) return;
    if (outcome == DownloadOutcome.paused) {
      handle.pause();
    } else {
      handle.cancel();
    }
  }

  /// Changes the aggregate throttle of the file currently transferring.
  set bytesPerSecond(int? value) => _current?.bytesPerSecond = value;

  void _attach(DownloadHandle handle) {
    _current = handle;
    // A stop requested between files still has to take effect.
    final outcome = _stop;
    if (outcome != null) {
      if (outcome == DownloadOutcome.paused) {
        handle.pause();
      } else {
        handle.cancel();
      }
    }
  }

  void _detach() => _current = null;
}

/// What `add` did.
class AddResult {
  const AddResult({
    required this.entry,
    required this.sourceId,
    required this.downloadedBytes,
    required this.dedupedBytes,
    required this.resumedBytes,
    this.outcome = DownloadOutcome.completed,
  });

  /// How the run ended. Only [DownloadOutcome.completed] means the variant is
  /// in the catalogue and ready to link.
  final DownloadOutcome outcome;

  bool get isComplete => outcome == DownloadOutcome.completed;

  final CatalogEntry entry;
  final String sourceId;

  /// Bytes that actually crossed the network this run — excluding both blobs
  /// already in the store and partial data resumed from an earlier attempt.
  final int downloadedBytes;

  /// Bytes that were already in the store and did not need downloading.
  final int dedupedBytes;

  /// Bytes recovered from an interrupted earlier attempt.
  final int resumedBytes;
}


/// What removing a variant from a tool did.
class UnlinkResult {
  const UnlinkResult({
    required this.targetId,
    required this.removed,
    required this.skipped,
  });

  final String targetId;

  /// Paths deleted from the target.
  final List<String> removed;

  /// Paths left alone because they were already gone, or because the file
  /// there is no longer the one Silo put down.
  final List<String> skipped;

  @override
  String toString() =>
      'UnlinkResult($targetId, ${removed.length} removed, '
      '${skipped.length} skipped)';
}

/// The library: sources on one side, targets on the other, a deduplicated
/// store in the middle.
///
/// This is the only class that knows about all three layers. The engine, the
/// sources and the targets stay unaware of each other by design, so adding a
/// mirror or a tool never means touching the other two.
class SiloLibrary {
  SiloLibrary({
    required this.store,
    required this.sources,
    required this.targets,
    ChunkedDownloader? downloader,
    DownloadOptions options = const DownloadOptions(),
  })  : _downloader = downloader ??
            ChunkedDownloader(
              client: ChunkedDownloader.createHttpClient(),
              options: options,
            ),
        _ownsDownloader = downloader == null;

  final BlobStore store;
  final List<ModelSource> sources;
  final List<DownloadTarget> targets;
  final ChunkedDownloader _downloader;
  final bool _ownsDownloader;

  File get catalogFile => File('${store.root.path}/catalog.json');

  Future<Catalog> readCatalog() => Catalog.read(catalogFile);

  DownloadTarget? targetById(String id) {
    for (final t in targets) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Lists the GGUF variants available for [ref] across every configured
  /// source, together with which sources carry it.
  Future<({List<ModelVariant> variants, List<ResolvedSource> sources})>
      inspect(
    ModelRef ref, {
    String? revision,
    void Function(String message)? onLog,
  }) async {
    final resolved = await resolveSources(
      sources,
      ref,
      revision: revision,
      onError: (source, error) =>
          onLog?.call('  ${source.id} unavailable: $error'),
    );
    if (resolved.isEmpty) {
      throw DownloadException('no source has ${ref.id}');
    }
    // Prefer the listing with the most complete digest coverage — a source
    // that publishes SHA-256 for every file lets everything be verified.
    resolved.sort((a, b) => _digestCoverage(b.listing)
        .compareTo(_digestCoverage(a.listing)));
    return (
      variants: groupVariants(resolved.first.listing.files, repoName: ref.repo),
      sources: resolved,
    );
  }

  /// Searches every source for [query] and merges the hits.
  ///
  /// The same repository usually exists on several hubs, so results are folded
  /// by `author/repo` and the sources that carry it are listed together — which
  /// is also a hint about download speed, since a repo on ModelScope will
  /// almost certainly come down faster from China.
  ///
  /// A source whose search fails is skipped. One hub being unreachable should
  /// not make searching impossible.
  Future<List<MergedSearchResult>> search(
    String query, {
    int limit = 25,
    bool localFormatsOnly = false,
    void Function(String message)? onLog,
  }) async {
    final perSource = await Future.wait<List<ModelSearchResult>>(
      sources.map((source) async {
        try {
          return await source.search(
            query,
            limit: limit,
            localFormatsOnly: localFormatsOnly,
          );
        } on Object catch (error) {
          onLog?.call('  ${source.id} search unavailable: $error');
          return const <ModelSearchResult>[];
        }
      }),
    );

    final merged = <String, MergedSearchResult>{};
    for (final results in perSource) {
      for (final result in results) {
        final String key = result.ref.id.toLowerCase();
        final MergedSearchResult? existing = merged[key];
        if (existing == null) {
          merged[key] = MergedSearchResult(
            primary: result,
            sourceIds: <String>[result.sourceId],
          );
          continue;
        }
        existing.sourceIds.add(result.sourceId);
        // Keep whichever hit carries more detail: HuggingFace supplies tags
        // that ModelScope does not, and either may report more downloads.
        if (result.tags.length > existing.primary.tags.length ||
            result.downloads > existing.primary.downloads) {
          merged[key] = MergedSearchResult(
            primary: result.tags.isNotEmpty ? result : existing.primary,
            sourceIds: existing.sourceIds,
          );
        }
      }
    }

    var hits = merged.values.toList();
    if (localFormatsOnly) {
      hits = hits.where((hit) => hit.primary.isLocalReady).toList();
    }
    hits.sort((a, b) => b.downloads.compareTo(a.downloads));
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  /// Downloads a variant into the store.
  ///
  /// Files already held under the same digest are skipped outright — that is
  /// deduplication paying off before a single byte moves.
  Future<AddResult> add(
    ModelRef ref, {
    String? variantName,
    String? revision,
    bool probeSourceSpeed = true,
    AddHandle? handle,
    void Function(AddProgress)? onProgress,
    void Function(String message)? onLog,
  }) async {
    await store.ensureCreated();

    final resolved = await resolveSources(
      sources,
      ref,
      revision: revision,
      onError: (source, error) =>
          onLog?.call('  ${source.id} unavailable: $error'),
    );
    if (resolved.isEmpty) {
      throw DownloadException('no source has ${ref.id}');
    }

    final ResolvedSource primary = _pickListingSource(resolved);
    final List<ModelVariant> variants =
        groupVariants(primary.listing.files, repoName: ref.repo);
    if (variants.isEmpty) {
      throw DownloadException(
        '${ref.id} has no GGUF or safetensors weights',
      );
    }

    final ModelVariant variant = _selectVariant(variants, variantName);
    if (!isShardSetComplete(variant.parts)) {
      throw DownloadException(
        'variant ${variant.name} has an incomplete shard set '
        '(${variant.parts.length} parts found)',
      );
    }

    // Order sources by measured throughput on a real file, not by config.
    var ordered = resolved;
    if (probeSourceSpeed && resolved.length > 1) {
      final speeds = await raceSources(resolved, variant.parts.first.path);
      for (final s in speeds) {
        onLog?.call('  ${s.source.displayName}: '
            '${s.ok ? '${(s.bytesPerSecond / (1 << 20)).toStringAsFixed(1)} MiB/s' : 'unavailable'}');
      }
      ordered = <ResolvedSource>[
        for (final speed in speeds)
          resolved.firstWhere((r) => r.source.id == speed.source.id),
      ];
    }

    final List<RemoteFile> wanted = variant.allFiles;
    final int totalBytes = variant.totalSize;
    final catalogFiles = <CatalogFile>[];
    var completedBytes = 0;
    var downloadedBytes = 0;
    var dedupedBytes = 0;
    var resumedBytes = 0;
    var usedSourceId = ordered.first.source.id;

    for (var i = 0; i < wanted.length; i++) {
      final RemoteFile file = wanted[i];
      final String? digest = _digestFor(file, ordered);

      if (digest != null && await store.has(digest)) {
        onLog?.call('  ${file.name}: already in store, skipping');
        catalogFiles.add(
          CatalogFile(name: file.name, sha256: digest, size: file.size),
        );
        completedBytes += file.size;
        dedupedBytes += file.size;
        continue;
      }

      final fetched = await _fetchOne(
        file: file,
        digest: digest,
        candidates: ordered,
        handle: handle,
        onProgress: onProgress == null
            ? null
            : (p) => onProgress(AddProgress(
                  fileName: file.name,
                  fileIndex: i,
                  fileCount: wanted.length,
                  file: p,
                  completedBytes: completedBytes,
                  totalBytes: totalBytes,
                  sourceId: usedSourceId,
                )),
        onLog: onLog,
      );

      downloadedBytes += fetched.transferred;

      if (fetched.outcome != DownloadOutcome.completed) {
        // Stopped part-way. Nothing is catalogued: a half-written variant that
        // looks installed is worse than one that plainly is not there.
        return AddResult(
          entry: CatalogEntry(
            ref: ref,
            variant: variant.name,
            sourceId: usedSourceId,
            revision: primary.listing.revision,
            directory: variant.directory,
            addedAt: DateTime.now(),
            files: catalogFiles,
          ),
          sourceId: usedSourceId,
          downloadedBytes: downloadedBytes,
          dedupedBytes: dedupedBytes,
          resumedBytes: resumedBytes,
          outcome: fetched.outcome,
        );
      }

      usedSourceId = fetched.sourceId;
      catalogFiles.add(
        CatalogFile(name: file.name, sha256: fetched.sha256, size: file.size),
      );
      completedBytes += file.size;
      resumedBytes += file.size - fetched.transferred;
    }

    // Provenance has to be self-consistent: the revision recorded must be the
    // one the bytes actually came from. Hubs disagree on branch names (`main`
    // vs `master`), so pairing the download source with the *listing* source's
    // revision would record a branch that does not exist on that hub.
    final ResolvedSource usedSource = ordered.firstWhere(
      (r) => r.source.id == usedSourceId,
      orElse: () => primary,
    );

    final entry = CatalogEntry(
      ref: ref,
      variant: variant.name,
      sourceId: usedSourceId,
      revision: usedSource.listing.revision,
      directory: variant.directory,
      addedAt: DateTime.now(),
      files: catalogFiles,
    );

    final catalog = await readCatalog();
    catalog.upsert(entry);
    await catalog.write(catalogFile);

    return AddResult(
      entry: entry,
      sourceId: usedSourceId,
      downloadedBytes: downloadedBytes,
      dedupedBytes: dedupedBytes,
      resumedBytes: resumedBytes,
    );
  }

  /// Downloads one file, failing over across sources.
  ///
  /// Because every source serves identical bytes under the same digest, a
  /// failure part-way through one mirror can be retried on another without
  /// throwing away what already landed.
  Future<({String sha256, String sourceId, int transferred, DownloadOutcome outcome})>
      _fetchOne({
    required RemoteFile file,
    required String? digest,
    required List<ResolvedSource> candidates,
    AddHandle? handle,
    void Function(DownloadProgress)? onProgress,
    void Function(String)? onLog,
  }) async {
    // Stage under the digest when known, otherwise under the path, so parallel
    // adds of the same file collide on one staging path rather than racing.
    final File staged = digest != null
        ? store.stagingFile(digest)
        : File('${store.tempDir.path}/${file.path.replaceAll('/', '_')}.part');

    Object? lastError;
    var transferred = 0;
    for (final candidate in candidates) {
      final Uri url = candidate.source.downloadUri(
        candidate.listing.ref,
        file.path,
        revision: candidate.listing.revision,
      );
      if (handle != null && handle.isStopping) {
        return (
          sha256: '',
          sourceId: candidate.source.id,
          transferred: transferred,
          outcome: handle.stopRequested!,
        );
      }

      try {
        final download = _downloader.download(
          url: url,
          target: staged,
          expectedSha256: digest,
          expectedSize: file.size > 0 ? file.size : null,
          options: _downloader.options.copyWith(
            headers: candidate.source.headers,
          ),
        );
        handle?._attach(download);
        download.progress.listen((p) {
          transferred = p.transferred;
          onProgress?.call(p);
        });

        final DownloadOutcome outcome = await download.done;
        handle?._detach();

        if (outcome != DownloadOutcome.completed) {
          // Pause and cancel are the user's decision, not a mirror failing, so
          // they must not send the loop off to try the next source.
          return (
            sha256: '',
            sourceId: candidate.source.id,
            transferred: transferred,
            outcome: outcome,
          );
        }

        // A source without a published digest still gets a digest — we just
        // have to compute it ourselves rather than verify against one.
        final String sha256 = digest ?? await sha256OfFile(staged);
        await store.ingest(staged, sha256);
        return (
          sha256: sha256,
          sourceId: candidate.source.id,
          transferred: transferred,
          outcome: DownloadOutcome.completed,
        );
      } on Object catch (error) {
        handle?._detach();
        lastError = error;
        onLog?.call('  ${file.name}: ${candidate.source.displayName} failed '
            '($error)');
        if (error is ChecksumMismatchException) {
          // Corrupt bytes are not resumable — start this file over elsewhere.
          await staged.delete().catchError((Object _) => staged);
          await File('${staged.path}.part.json')
              .delete()
              .catchError((Object _) => File('${staged.path}.part.json'));
        }
      }
    }
    throw DownloadException(
      'every source failed for ${file.path}: $lastError',
    );
  }

  /// Installs a catalogued variant into the given targets.
  Future<List<InstallResult>> link(
    ModelRef ref, {
    required List<String> targetIds,
    String? variantName,
  }) async {
    final catalog = await readCatalog();
    final List<CatalogEntry> candidates = catalog.forModel(ref);
    if (candidates.isEmpty) {
      throw StateError('${ref.id} is not in the library; run `silo add` first');
    }

    final CatalogEntry entry = variantName == null
        ? candidates.first
        : candidates.firstWhere(
            (e) => e.variant == variantName,
            orElse: () => throw StateError(
              'variant $variantName is not in the library for ${ref.id}',
            ),
          );

    final results = <InstallResult>[];
    for (final String id in targetIds) {
      final DownloadTarget? target = targetById(id);
      if (target == null) {
        throw ArgumentError('unknown target: $id');
      }

      final files = <TargetFile>[
        for (final f in entry.files)
          TargetFile(sha256: f.sha256, relativePath: f.name),
      ];

      // Fail before touching the filesystem if a blob went missing.
      for (final f in files) {
        if (!await store.has(f.sha256)) {
          throw StateError(
            'blob ${f.sha256} for ${f.relativePath} is missing from the store',
          );
        }
      }

      final InstallResult result = await target.install(
        entry.ref,
        files,
        store,
        directory: entry.directory,
      );
      results.add(result);

      // Linking converges the directory on what should be there. A file this
      // library placed earlier and no longer wants — because the target has
      // since learned to leave it out — is removed, so an install that was
      // already wrong repairs itself on the next link rather than staying
      // broken until someone deletes it by hand.
      await _removeStaleLinks(
        catalog: catalog,
        entryKey: entry.key,
        targetId: target.id,
        keepPaths: result.links.map((l) => l.path).toSet(),
      );

      catalog.recordLinks(<LinkRecord>[
        for (final l in result.links)
          LinkRecord(
            entryKey: entry.key,
            targetId: target.id,
            sha256: l.sha256,
            path: l.path,
            hardLinked: l.method != LinkMethod.copy,
          ),
      ]);
    }

    await catalog.write(catalogFile);
    return results;
  }

  /// Deletes blobs no catalogued variant references.
  ///
  /// [freedBytes] is what the disk actually gave back. [retainedBytes] is data
  /// that was dropped from the store but is still hard-linked into a tool, so it
  /// cost nothing to keep and nothing to remove — the tool goes on using it.
  /// Reporting the two together as "reclaimed" would overstate the result every
  /// time a forgotten model is still installed somewhere.
  Future<({int blobs, int freedBytes, int retainedBytes})> gc({
    bool dryRun = false,
  }) async {
    final List<String> orphans = await _orphanBlobs();

    var freed = 0;
    var retained = 0;
    for (final String sha256 in orphans) {
      if (dryRun) {
        final int size = await store.blobFile(sha256).length();
        final int? links = await linkCountOf(store.blobFile(sha256).path);
        if (links == null || links > 1) {
          retained += size;
        } else {
          freed += size;
        }
      } else {
        final result = await store.remove(sha256);
        freed += result.freed;
        retained += result.retained;
      }
    }
    if (!dryRun) {
      freed += await store.pruneStaging();
    }
    return (blobs: orphans.length, freedBytes: freed, retainedBytes: retained);
  }

  /// Bytes sitting in the store that no catalogued variant references.
  ///
  /// Surfaced so the space is visible before someone goes looking for it: a
  /// store larger than the sum of its models is otherwise unexplained.
  Future<({int blobs, int bytes})> reclaimable() async {
    final List<String> orphans = await _orphanBlobs();
    var bytes = 0;
    for (final String sha256 in orphans) {
      bytes += await store.blobFile(sha256).length();
    }
    return (blobs: orphans.length, bytes: bytes);
  }

  Future<List<String>> _orphanBlobs() async {
    final catalog = await readCatalog();
    final Set<String> referenced = catalog.referencedBlobs();
    final List<String> present = await store.listBlobs();
    return present.where((sha256) => !referenced.contains(sha256)).toList();
  }

  /// Deletes files recorded for this entry and target that are no longer
  /// wanted, using the same "is it still ours" check as [unlink].
  Future<void> _removeStaleLinks({
    required Catalog catalog,
    required String entryKey,
    required String targetId,
    required Set<String> keepPaths,
  }) async {
    final stale = catalog
        .linksFor(entryKey)
        .where((link) => link.targetId == targetId)
        .where((link) => !keepPaths.contains(link.path))
        .toList();
    if (stale.isEmpty) return;

    final removed = <String>[];
    for (final link in stale) {
      final file = File(link.path);
      if (!await file.exists()) {
        removed.add(link.path);
        continue;
      }
      if (!await _isOursToDelete(link: link, file: file)) continue;
      await file.delete();
      removed.add(link.path);
    }

    catalog.links.removeWhere(
      (link) => link.entryKey == entryKey &&
          link.targetId == targetId &&
          removed.contains(link.path),
    );
    await _pruneEmptyDirectories(paths: removed);
  }

  /// Removes a variant's files from tools it was linked into.
  ///
  /// Only paths this library recorded are touched, and only when the file there
  /// is still the one it put down — matched by inode against the blob. A file
  /// the user replaced by hand is left alone and reported as skipped, because
  /// deleting something Silo did not create would be unforgivable for a tool
  /// that writes into other applications' directories.
  Future<List<UnlinkResult>> unlink(
    ModelRef ref, {
    String? variantName,
    List<String>? targetIds,
  }) async {
    final catalog = await readCatalog();
    final Set<String>? wanted = targetIds?.toSet();

    final List<CatalogEntry> entries = catalog
        .forModel(ref)
        .where((e) => variantName == null || e.variant == variantName)
        .toList();

    final byTarget = <String, ({List<String> removed, List<String> skipped})>{};

    for (final entry in entries) {
      for (final link in catalog.linksFor(entry.key)) {
        if (wanted != null && !wanted.contains(link.targetId)) continue;

        final bucket = byTarget.putIfAbsent(
          link.targetId,
          () => (removed: <String>[], skipped: <String>[]),
        );

        final file = File(link.path);
        if (!await file.exists()) {
          // Already gone; nothing to do, and no reason to complain.
          continue;
        }
        if (!await _isOursToDelete(link: link, file: file)) {
          bucket.skipped.add(link.path);
          continue;
        }

        await file.delete();
        bucket.removed.add(link.path);
      }

      catalog.dropLinks(entry.key, targetIds: wanted);
    }

    await _pruneEmptyDirectories(
      paths: <String>[
        for (final bucket in byTarget.values) ...bucket.removed,
      ],
    );
    await catalog.write(catalogFile);

    return <UnlinkResult>[
      for (final entry in byTarget.entries)
        UnlinkResult(
          targetId: entry.key,
          removed: entry.value.removed,
          skipped: entry.value.skipped,
        ),
    ];
  }

  /// True when the file at [link] is still the one this library placed there.
  ///
  /// A hard link is the same inode as its blob. Once the blob is gone there is
  /// nothing left to compare against, so the record is trusted — it is the only
  /// evidence either way, and it was written when the file was created.
  Future<bool> _isOursToDelete({
    required LinkRecord link,
    required File file,
  }) async {
    if (!link.hardLinked) {
      // A copy shares no inode with anything; the record is all there is.
      return true;
    }
    final File blob = store.blobFile(link.sha256);
    if (!await blob.exists()) return true;

    final String? blobInode = await inodeIdOf(blob.path);
    final String? fileInode = await inodeIdOf(file.path);
    if (blobInode == null || fileInode == null) return true;
    return blobInode == fileInode;
  }

  /// Removes directories left empty by unlinking, up to each target's root.
  Future<void> _pruneEmptyDirectories({required List<String> paths}) async {
    final roots = <String>{for (final target in targets) target.root.path};

    for (final path in paths) {
      var dir = File(path).parent;
      while (!roots.contains(dir.path) &&
          roots.any((root) => dir.path.startsWith(root))) {
        try {
          if (await dir.list().isEmpty) {
            await dir.delete();
          } else {
            break;
          }
        } on FileSystemException {
          break;
        }
        dir = dir.parent;
      }
    }
  }

  /// Forgets a variant, leaving `gc` to reclaim its blobs.
  ///
  /// Unlinks from every tool first by default. Forgetting a model while its
  /// files stay hard-linked into LM Studio would mean `gc` could never actually
  /// free the space — the other link keeps the data alive — so the two have to
  /// happen together to mean anything. Pass `unlinkFirst: false` to keep the
  /// files where they are and only stop tracking them.
  Future<bool> forget(
    ModelRef ref, {
    String? variantName,
    bool unlinkFirst = true,
  }) async {
    if (unlinkFirst) {
      await unlink(ref, variantName: variantName);
    }

    final catalog = await readCatalog();
    final List<CatalogEntry> matches = catalog
        .forModel(ref)
        .where((e) => variantName == null || e.variant == variantName)
        .toList();
    if (matches.isEmpty) return false;
    for (final entry in matches) {
      catalog.remove(entry.key);
    }
    await catalog.write(catalogFile);
    return true;
  }

  void close() {
    if (_ownsDownloader) _downloader.close();
  }

  ModelVariant _selectVariant(List<ModelVariant> variants, String? name) {
    if (name == null) {
      // Q4_K_M is the everyday default: roughly a quarter of F16 with little
      // quality loss, and what most people would pick by hand anyway.
      for (final v in variants) {
        if (v.quantization == 'Q4_K_M') return v;
      }
      return variants.first;
    }
    final String needle = name.toLowerCase();
    for (final v in variants) {
      if (v.name.toLowerCase() == needle) return v;
    }
    for (final v in variants) {
      if (v.quantization?.toLowerCase() == needle) return v;
    }
    final matches = variants
        .where((v) => v.name.toLowerCase().contains(needle))
        .toList();
    if (matches.length == 1) return matches.single;
    throw ArgumentError(
      matches.isEmpty
          ? 'no variant matches "$name"; available: '
              '${variants.map((v) => v.name).join(', ')}'
          : '"$name" is ambiguous: ${matches.map((v) => v.name).join(', ')}',
    );
  }

  ResolvedSource _pickListingSource(List<ResolvedSource> resolved) {
    final sorted = List<ResolvedSource>.of(resolved)
      ..sort((a, b) =>
          _digestCoverage(b.listing).compareTo(_digestCoverage(a.listing)));
    return sorted.first;
  }

  /// Looks for a digest across every source's listing, since one hub may
  /// publish it where another does not.
  String? _digestFor(RemoteFile file, List<ResolvedSource> candidates) {
    if (file.sha256 != null) return file.sha256;
    for (final candidate in candidates) {
      final RemoteFile? match = candidate.listing.fileAt(file.path);
      if (match?.sha256 != null) return match!.sha256;
    }
    return null;
  }
}

double _digestCoverage(ModelListing listing) {
  if (listing.files.isEmpty) return 0;
  final int withDigest =
      listing.files.where((f) => f.sha256 != null).length;
  return withDigest / listing.files.length;
}
