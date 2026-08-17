import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_core/silo_core.dart';

/// Distributing stored models into local tools, and reclaiming space.
///
/// Linking after a download is the queue's job — each job carries the targets it
/// was queued for. What is left here is linking on demand, from the stored
/// library, after the fact.
extension LibraryLogicLink on LibraryLogic {
  void toggleTarget({required String targetId}) {
    if (state.selectedTargetIds.contains(targetId)) {
      state.selectedTargetIds.remove(targetId);
    } else {
      state.selectedTargetIds.add(targetId);
    }
    update(<Object>[LibraryUpdateType.targets]);
  }

  /// Hard-links a stored variant into every selected target.
  Future<void> linkEntry({
    required ModelRef ref,
    required String variantName,
  }) async {
    final targetIds = state.selectedTargetIds.toList();
    if (targetIds.isEmpty) return;

    try {
      await library.link(
        ref,
        targetIds: targetIds,
        variantName: variantName,
      );
      state.errorMessage = null;
    } on Object catch (error) {
      state.errorMessage = '$error';
    }

    await loadStored();
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
  ///
  /// Records what the disk actually gave back separately from what was dropped
  /// but is still hard-linked into a tool — that data keeps working where it is
  /// linked, and claiming it as reclaimed would overstate the result.
  Future<void> reclaimSpace() async {
    final result = await library.gc();
    state.lastGcBlobs = result.blobs;
    state.lastGcFreedBytes = result.freedBytes;
    state.lastGcRetainedBytes = result.retainedBytes;
    await loadStored();
  }
}
