import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_core/silo_core.dart';

/// Putting work on the queue and steering it.
///
/// Nothing here awaits a download. The queue runs on its own and reports
/// through [LibraryLogic.queue]'s change stream, so the UI stays responsive and
/// a user can keep browsing and queueing while something transfers.
extension LibraryLogicDownload on LibraryLogic {
  /// Queues the selected variant, to be linked into the selected targets when
  /// it finishes.
  void enqueueSelected() {
    final ref = state.inspectedRef;
    final variant = state.selectedVariant;
    if (ref == null || variant == null) return;

    queue.enqueue(
      ref: ref,
      variantName: variant.name,
      targetIds: state.selectedTargetIds.toList(),
    );
  }

  void pauseJob({required String jobId}) => queue.pause(jobId);

  void resumeJob({required String jobId}) => queue.resume(jobId);

  void cancelJob({required String jobId}) => queue.cancel(jobId);

  void removeJob({required String jobId}) => queue.remove(jobId);

  void moveJobUp({required String jobId}) => queue.moveUp(jobId);

  void moveJobDown({required String jobId}) => queue.moveDown(jobId);

  void clearFinishedJobs() => queue.clearFinished();

  /// Holds the whole queue, or releases it.
  void toggleQueueHold() {
    if (queue.isHalted) {
      queue.resumeAll();
    } else {
      queue.pauseAll();
    }
  }

  /// Called for every queue change, including progress ticks.
  ///
  /// Only the queue section is rebuilt here. Progress arrives several times a
  /// second, and rebuilding the variant table and the stored-model list at that
  /// rate would be wasted work.
  void onQueueChanged(DownloadQueue queue) {
    update(<Object>[LibraryUpdateType.queue]);

    // The library only changes when something finishes, so refresh it then
    // rather than on every tick.
    final int finished =
        queue.jobs.where((job) => job.isFinished).length;
    if (finished != state.lastFinishedCount) {
      state.lastFinishedCount = finished;
      loadStored();
    }
  }
}
