import 'dart:io';

import 'package:get/get.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

/// Owns the one [SiloLibrary] the window talks to.
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

  @override
  void onInit() {
    super.onInit();
    state.targets = library.targets;
    loadStored();
  }

  @override
  void onClose() {
    library.close();
    state.dispose();
    super.onClose();
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

    state.catalog = catalog;
    state.storeBytes = await store.totalSize();
    state.logicalBytes = catalogued + linked;
    state.presentTargetIds = present;
    update(<Object>[LibraryUpdateType.stored, LibraryUpdateType.targets]);
  }

  /// Opens a path in Finder.
  Future<void> revealInFinder({required String path}) async {
    await Process.run('/usr/bin/open', <String>[path]);
  }
}
