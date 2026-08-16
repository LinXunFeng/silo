import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_core/silo_core.dart';

/// Distributing stored models into local tools, and reclaiming space.
extension LibraryLogicLink on LibraryLogic {
  void toggleTarget({required String targetId}) {
    if (state.selectedTargetIds.contains(targetId)) {
      state.selectedTargetIds.remove(targetId);
    } else {
      state.selectedTargetIds.add(targetId);
    }
    update(<Object>[LibraryUpdateType.targets]);
  }

  /// Links the variant that just finished downloading.
  Future<void> linkActiveToSelectedTargets() async {
    final ref = state.activeRef;
    final variantName = state.activeVariantName;
    if (ref == null || variantName == null) return;
    await linkEntry(ref: ref, variantName: variantName);
  }

  /// Hard-links a stored variant into every selected target.
  Future<void> linkEntry({
    required ModelRef ref,
    required String variantName,
  }) async {
    final targetIds = state.selectedTargetIds.toList();
    if (targetIds.isEmpty) return;

    try {
      final results = await library.link(
        ref,
        targetIds: targetIds,
        variantName: variantName,
      );

      var visible = 0;
      var cost = 0;
      for (final result in results) {
        visible += result.apparentSize;
        cost += result.bytesOnDisk;
      }
      state.lastLinkVisibleBytes = visible;
      state.lastLinkCostBytes = cost;
      state.errorMessage = null;
    } on Object catch (error) {
      state.errorMessage = '$error';
    }

    await loadStored();
    update(<Object>[LibraryUpdateType.download]);
  }

  /// Forgets a variant. Its blobs survive until [reclaimSpace] runs, so a
  /// mistaken removal costs nothing but a second click.
  Future<void> forgetEntry({
    required ModelRef ref,
    required String variantName,
  }) async {
    await library.forget(ref, variantName: variantName);
    await loadStored();
  }

  /// Deletes blobs nothing references.
  Future<void> reclaimSpace() async {
    final result = await library.gc();
    state.lastGcBlobs = result.blobs;
    state.lastGcBytes = result.bytes;
    await loadStored();
  }
}
