import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic_download.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

/// Owns the one [SiloLibrary] and the one [DownloadQueue] the window talks to.
///
/// Sources and targets are assembled here and nowhere else, mirroring the CLI's
/// single wiring point, so adding either stays a one-line change.
class LibraryLogic extends GetxController {
  final LibraryState state = LibraryState();

  late final BlobStore store = BlobStore.defaultLocation();

  late final SiloLibrary library = SiloLibrary(
    store: store,
    sources: <ModelSource>[
      HuggingFaceSource.mirror(),
      ModelScopeSource(),
      HuggingFaceSource(),
    ],
    targets: <DownloadTarget>[LmStudioTarget()],
  );

  /// Shares its queue file with the CLI, so a run interrupted in one shows up
  /// in the other.
  late final DownloadQueue queue = DownloadQueue(library: library);

  StreamSubscription<DownloadQueue>? _queueSubscription;

  @override
  void onInit() {
    super.onInit();
    state.targets = library.targets;
    _queueSubscription = queue.changes.listen(onQueueChanged);
    unawaited(_restoreQueue());
    loadStored();
  }

  @override
  void onClose() {
    unawaited(_queueSubscription?.cancel());
    unawaited(queue.close());
    library.close();
    state.dispose();
    super.onClose();
  }

  /// Picks up whatever the last session left behind.
  ///
  /// Restored jobs are paused and stay that way until asked — reopening the
  /// window should not start a multi-gigabyte transfer on its own.
  Future<void> _restoreQueue() async {
    await queue.load();
    state.restoredJobCount = queue.jobs.length;
    update(<Object>[LibraryUpdateType.queue]);
  }

  /// Reloads the catalogue, store size and target availability.
  Future<void> loadStored() async {
    final catalog = await library.readCatalog();
    final present = <String>{};
    for (final target in state.targets) {
      if (await target.isPresent()) present.add(target.id);
    }

    // Logical size is what these files would have cost stored the ordinary
    // way: every catalogued file, plus a full copy per hard link a tool sees.
    final sizeByDigest = <String, int>{
      for (final entry in catalog.entries)
        for (final file in entry.files) file.sha256: file.size,
    };
    final catalogued =
        catalog.entries.fold<int>(0, (sum, e) => sum + e.totalSize);
    final linked = catalog.links
        .where((link) => link.hardLinked)
        .fold<int>(0, (sum, link) => sum + (sizeByDigest[link.sha256] ?? 0));

    final reclaimable = await library.reclaimable();

    state.catalog = catalog;
    state.storeBytes = await store.totalSize();
    state.logicalBytes = catalogued + linked;
    state.reclaimableBytes = reclaimable.bytes;
    state.presentTargetIds = present;
    update(<Object>[LibraryUpdateType.stored, LibraryUpdateType.targets]);
  }

  /// Opens a path in Finder.
  Future<void> revealInFinder({required String path}) async {
    await Process.run('/usr/bin/open', <String>[path]);
  }
}
