// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Silo';

  @override
  String get tagline => 'Download once, link everywhere.';

  @override
  String get searchLabel => 'Model';

  @override
  String get searchPlaceholder => 'a keyword, author/repo, or a hub URL';

  @override
  String get searchAction => 'Look up';

  @override
  String get searching => 'Looking up sources…';

  @override
  String availableFrom(String sources) {
    return 'Available from $sources';
  }

  @override
  String get variantsTitle => 'Variants';

  @override
  String variantShards(int count) {
    return '$count shards';
  }

  @override
  String variantProjector(int count) {
    return '+$count mmproj';
  }

  @override
  String variantSupportFiles(int count) {
    return '+$count support files';
  }

  @override
  String get pauseAction => 'Pause';

  @override
  String get resumeAction => 'Resume';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get linkAction => 'Link';

  @override
  String get removeAction => 'Remove';

  @override
  String get reclaimAction => 'Reclaim space';

  @override
  String get refreshAction => 'Refresh';

  @override
  String get revealAction => 'Show in Finder';

  @override
  String downloadFile(String name, int index, int count) {
    return '$name ($index of $count)';
  }

  @override
  String downloadStats(String received, String total, String rate, String eta) {
    return '$received of $total · $rate · $eta left';
  }

  @override
  String downloadConnections(int active, int done, int total) {
    return '$active connections · $done/$total chunks';
  }

  @override
  String get statusResolving => 'Resolving sources…';

  @override
  String get statusVerifying => 'Verifying checksum…';

  @override
  String get statusPaused => 'Paused — resume to continue where it stopped';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String statusDone(String name) {
    return 'Added $name';
  }

  @override
  String get unknownValue => '—';

  @override
  String get libraryTitle => 'Library';

  @override
  String get libraryEmpty =>
      'Nothing stored yet. Look up a model to get started.';

  @override
  String librarySummary(int models, String size) {
    return '$models models · $size on disk';
  }

  @override
  String librarySaved(String size) {
    return 'Deduplication saved $size';
  }

  @override
  String entryLinkedTo(String targets) {
    return 'Linked into $targets';
  }

  @override
  String get entryNotLinked => 'Not linked yet';

  @override
  String entrySource(String source, String revision) {
    return '$source · $revision';
  }

  @override
  String get targetsTitle => 'Link into';

  @override
  String get targetNotInstalled => 'not installed';

  @override
  String linkedResult(String visible, String cost) {
    return '$visible visible, $cost extra on disk';
  }

  @override
  String reclaimedSpace(String size, int count) {
    return 'Freed $size across $count blobs';
  }

  @override
  String get reclaimNothing => 'Nothing to reclaim';

  @override
  String sourceSpeed(String source, String rate) {
    return '$source: $rate';
  }

  @override
  String sourceUnavailable(String source) {
    return '$source: unavailable';
  }

  @override
  String get queueTitle => 'Queue';

  @override
  String get queueEmpty => 'Nothing queued.';

  @override
  String get queueAddAction => 'Add to queue';

  @override
  String queueSummary(int pending) {
    return '$pending waiting';
  }

  @override
  String get queuePauseAllAction => 'Hold queue';

  @override
  String get queueResumeAllAction => 'Start queue';

  @override
  String get queueClearAction => 'Clear finished';

  @override
  String get queueHeldNotice =>
      'Queue is held — nothing will start until you resume it.';

  @override
  String queueRestoredNotice(int count) {
    return '$count jobs restored from the last session, paused.';
  }

  @override
  String get jobStatusQueued => 'Waiting';

  @override
  String get jobStatusRunning => 'Downloading';

  @override
  String get jobStatusPaused => 'Paused';

  @override
  String get jobStatusCompleted => 'Done';

  @override
  String get jobStatusCancelled => 'Cancelled';

  @override
  String get jobStatusFailed => 'Failed';

  @override
  String get moveUpAction => 'Move up';

  @override
  String get moveDownAction => 'Move down';

  @override
  String get removeFromQueueAction => 'Remove';

  @override
  String libraryReclaimable(String size) {
    return '$size unreferenced — reclaim to free it';
  }

  @override
  String get unlinkAction => 'Unlink';

  @override
  String gcResult(String freed, int count) {
    return 'Freed $freed across $count blobs';
  }

  @override
  String gcRetained(String size) {
    return '$size not reclaimed — still installed in a tool';
  }

  @override
  String unlinkSkipped(int count) {
    return '$count file(s) left alone — not what Silo put there';
  }

  @override
  String get searchResultsTitle => 'Search results';

  @override
  String get searchNoResults => 'Nothing matched. Try a different keyword.';

  @override
  String get searchShowAll => 'Include transformers-only repositories';

  @override
  String resultDownloads(String count) {
    return '$count downloads';
  }

  @override
  String resultOnSources(String sources) {
    return 'on $sources';
  }

  @override
  String get reclaimTooltip =>
      'Delete stored files no model in the library refers to';

  @override
  String get refreshTooltip => 'Re-read the store and the tool directories';

  @override
  String reclaimConfirmTitle(String size) {
    return 'Reclaim $size?';
  }

  @override
  String reclaimConfirmBody(int count) {
    return '$count stored file(s) are no longer referred to by any model in the library. Models installed in your tools are not touched.';
  }

  @override
  String get reclaimConfirmAction => 'Reclaim';

  @override
  String get confirmOkAction => 'OK';
}
