import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';

/// Which of the four sections the content area is showing.
extension LibraryLogicSection on LibraryLogic {
  void selectSection({required LibrarySection section}) {
    if (state.selectedSection == section) return;
    state.selectedSection = section;
    update(<Object>[LibraryUpdateType.navigation]);
  }

  /// Redraws the sidebar only when a badge would actually change.
  ///
  /// The queue reports progress several times a second; the number of jobs in
  /// it changes far less often, and that is all the nav shows.
  void refreshNavigationCounts() {
    final int jobCount = queue.jobs.length;
    if (jobCount == state.lastNavigationJobCount) return;
    state.lastNavigationJobCount = jobCount;
    update(<Object>[LibraryUpdateType.navigation]);
  }

  /// Jumps to the queue after something is added, so the button that queued it
  /// visibly leads somewhere.
  void showQueueSection() {
    selectSection(section: LibrarySection.queue);
  }
}
