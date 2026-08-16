import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_link.dart';
import 'package:silo_core/silo_core.dart';

/// Running, pausing and cancelling a download.
extension LibraryLogicDownload on LibraryLogic {
  /// Downloads the selected variant into the store.
  ///
  /// Resuming is the same call: a paused run left its `.part.json` sidecars in
  /// place, so starting again picks up mid-file rather than from zero.
  Future<void> startDownload() async {
    final ref = state.inspectedRef;
    final variant = state.selectedVariant;
    if (ref == null || variant == null || state.isDownloading) return;

    final handle = AddHandle();
    state.addHandle = handle;
    state.activeRef = ref;
    state.activeVariantName = variant.name;
    state.status = LibraryStatus.resolving;
    state.progress = null;
    state.statusDetail = null;
    state.errorMessage = null;
    update(<Object>[LibraryUpdateType.download]);

    try {
      final result = await library.add(
        ref,
        variantName: variant.name,
        handle: handle,
        onLog: _onLog,
        onProgress: _onProgress,
      );

      switch (result.outcome) {
        case DownloadOutcome.completed:
          state.status = LibraryStatus.done;
          state.statusDetail = null;
          await loadStored();
          // Linking straight after a download is what the user came for, so
          // do it rather than making them press a second button.
          await linkActiveToSelectedTargets();
        case DownloadOutcome.paused:
          state.status = LibraryStatus.paused;
        case DownloadOutcome.cancelled:
          state.status = LibraryStatus.cancelled;
      }
    } on Object catch (error) {
      state.status = LibraryStatus.failed;
      state.errorMessage = '$error';
    } finally {
      state.addHandle = null;
      update(<Object>[LibraryUpdateType.download]);
    }
  }

  void pauseDownload() {
    state.addHandle?.pause();
    update(<Object>[LibraryUpdateType.download]);
  }

  void cancelDownload() {
    state.addHandle?.cancel();
    update(<Object>[LibraryUpdateType.download]);
  }

  /// Resumes a paused run by issuing the same add again.
  Future<void> resumeDownload() async {
    final ref = state.activeRef;
    final variantName = state.activeVariantName;
    if (ref == null || variantName == null) return;

    state.inspectedRef = ref;
    state.selectedVariantName = variantName;
    await startDownload();
  }

  void _onLog(String message) {
    state.statusDetail = message.trim();
    update(<Object>[LibraryUpdateType.download]);
  }

  void _onProgress(AddProgress progress) {
    state.progress = progress;
    // The engine reports no separate verification phase, but a file sitting at
    // 100% with the run still going is exactly that — and on a multi-gigabyte
    // shard the silence would otherwise read as a hang.
    final atEnd = progress.file.fraction == 1.0;
    state.status =
        atEnd ? LibraryStatus.verifying : LibraryStatus.downloading;
    update(<Object>[LibraryUpdateType.download]);
  }
}
