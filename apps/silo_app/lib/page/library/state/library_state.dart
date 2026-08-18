import 'package:flutter/widgets.dart';
import 'package:silo_core/silo_core.dart';

class LibraryState {
  /// Root context, for anything that needs one outside a build method.
  BuildContext? rootContext;

  final TextEditingController searchController = TextEditingController();

  // ── Lookup ────────────────────────────────────────────────────────────────

  bool isSearching = false;

  String? errorMessage;

  /// Keyword hits, when the query was not a precise `author/repo`.
  List<MergedSearchResult> searchResults = <MergedSearchResult>[];

  /// Whether to include repositories no local runner can load.
  bool includeAllFormats = false;

  /// The repository currently being inspected.
  ModelRef? inspectedRef;

  List<ModelVariant> variants = <ModelVariant>[];

  /// Source ids that carry [inspectedRef], fastest-first once measured.
  List<String> availableSourceIds = <String>[];

  String? selectedVariantName;

  ModelVariant? get selectedVariant {
    final name = selectedVariantName;
    if (name == null) return null;
    for (final variant in variants) {
      if (variant.name == name) return variant;
    }
    return null;
  }

  // ── Queue ─────────────────────────────────────────────────────────────────

  /// Jobs restored from a previous session, so the UI can say so once.
  int restoredJobCount = 0;

  /// How many jobs had finished last time the library was reloaded, so a
  /// completion can be noticed without reloading on every progress tick.
  int lastFinishedCount = 0;

  // ── Stored library ────────────────────────────────────────────────────────

  Catalog catalog = Catalog();

  int storeBytes = 0;

  /// Bytes the same files would have cost stored conventionally.
  int logicalBytes = 0;

  /// Bytes in the store that no catalogued model references. Without this the
  /// store's size is simply larger than the models in it, with no explanation.
  int reclaimableBytes = 0;

  int get savedBytes {
    final saved = logicalBytes - storeBytes;
    return saved > 0 ? saved : 0;
  }

  // ── Targets ───────────────────────────────────────────────────────────────

  List<DownloadTarget> targets = <DownloadTarget>[];

  /// Target ids that exist on this machine.
  Set<String> presentTargetIds = <String>{};

  Set<String> selectedTargetIds = <String>{'lmstudio'};

  // ── Housekeeping ──────────────────────────────────────────────────────────

  /// Files the last unlink refused to delete because they were no longer the
  /// ones Silo put there.
  int? lastUnlinkSkipped;

  int? lastGcBlobs;
  int? lastGcFreedBytes;

  /// Dropped from the store but still hard-linked into a tool, so no space came
  /// back. Kept apart from [lastGcFreedBytes] so the report stays truthful.
  int? lastGcRetainedBytes;

  void dispose() {
    searchController.dispose();
  }
}
