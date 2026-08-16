import 'package:flutter/widgets.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_core/silo_core.dart';

class LibraryState {
  /// Root context, for anything that needs one outside a build method.
  BuildContext? rootContext;

  final TextEditingController searchController = TextEditingController();

  // ── Lookup ────────────────────────────────────────────────────────────────

  bool isSearching = false;

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

  // ── Download ──────────────────────────────────────────────────────────────

  LibraryStatus status = LibraryStatus.idle;

  /// Non-null while a run is in flight; the handle that pauses or cancels it.
  AddHandle? addHandle;

  AddProgress? progress;

  /// The model a run is working on, so the UI keeps naming it after the
  /// selection changes underneath.
  ModelRef? activeRef;
  String? activeVariantName;

  /// Free-form line under the progress bar: source speeds, failures, results.
  String? statusDetail;

  String? errorMessage;

  bool get isDownloading =>
      status == LibraryStatus.resolving ||
      status == LibraryStatus.downloading ||
      status == LibraryStatus.verifying;

  bool get canPause => status == LibraryStatus.downloading;

  // ── Stored library ────────────────────────────────────────────────────────

  Catalog catalog = Catalog();

  int storeBytes = 0;

  /// Bytes the same files would have cost stored conventionally.
  int logicalBytes = 0;

  int get savedBytes {
    final saved = logicalBytes - storeBytes;
    return saved > 0 ? saved : 0;
  }

  // ── Targets ───────────────────────────────────────────────────────────────

  List<DownloadTarget> targets = <DownloadTarget>[];

  /// Target ids that exist on this machine.
  Set<String> presentTargetIds = <String>{};

  Set<String> selectedTargetIds = <String>{'lmstudio'};

  /// Result of the most recent link, for the "0 B extra on disk" line that
  /// makes the dedup claim concrete rather than a slogan.
  int? lastLinkVisibleBytes;
  int? lastLinkCostBytes;

  // ── Housekeeping ──────────────────────────────────────────────────────────

  int? lastGcBlobs;
  int? lastGcBytes;

  void dispose() {
    searchController.dispose();
  }
}
