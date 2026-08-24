import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/format/byte_format.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';
import 'package:silo_app/common/widget/app_card.dart';
import 'package:silo_app/common/widget/app_empty_state.dart';
import 'package:silo_app/common/widget/app_notice.dart';
import 'package:silo_app/common/widget/app_page_header.dart';
import 'package:silo_app/common/widget/app_status_pill.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_download.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

/// Work in flight, one job per card.
class LibraryQueueView extends StatefulWidget {
  const LibraryQueueView({super.key});

  @override
  State<LibraryQueueView> createState() => _LibraryQueueViewState();
}

class _LibraryQueueViewState extends State<LibraryQueueView>
    with LibraryLogicConsumerMixin<LibraryQueueView> {
  LibraryState get state => logic.state;

  DownloadQueue get queue => logic.queue;

  AppLocalizations get l10n => AppLocalizations.of(context);

  AppPalette get palette => AppPalette.of(context);

  MacosTypography get typography => MacosTheme.of(context).typography;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.queue,
      builder: (_) => _buildBody(),
    );
  }

  Widget _buildBody() {
    final jobs = queue.jobs;

    final jobCards = <Widget>[
      for (final job in jobs) _buildJob(job: job, jobs: jobs),
    ];

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildHeader(),
        const SizedBox(height: AppSpacing.xl),
        ..._buildNotices(),
        if (jobs.isEmpty) _buildEmpty(),
        ...jobCards,
      ],
    );
    return resultWidget;
  }

  Widget _buildHeader() {
    return AppPageHeader(
      title: l10n.queueTitle,
      caption: queue.pendingCount == 0
          ? null
          : l10n.queueSummary(queue.pendingCount),
      subtitle: l10n.queueSubtitle,
      actions: _buildHeaderActions(),
    );
  }

  /// Both buttons are always rendered, disabled rather than removed.
  ///
  /// Otherwise they shift sideways as jobs finish: aiming at "hold queue" just
  /// as the last download completes would land on "clear finished" instead,
  /// because that button slides into the vacated spot.
  List<Widget> _buildHeaderActions() {
    final bool anyFinished = queue.jobs.any((job) => job.isFinished);
    final bool anyPending = queue.jobs.any((job) => !job.isFinished);

    return <Widget>[
      PushButton(
        controlSize: ControlSize.regular,
        secondary: true,
        onPressed: anyFinished ? logic.clearFinishedJobs : null,
        child: Text(l10n.queueClearAction),
      ),
      const SizedBox(width: AppSpacing.sm),
      PushButton(
        controlSize: ControlSize.regular,
        secondary: !queue.isHalted,
        onPressed: anyPending ? logic.toggleQueueHold : null,
        child: Text(
          queue.isHalted
              ? l10n.queueResumeAllAction
              : l10n.queuePauseAllAction,
        ),
      ),
    ];
  }

  Widget _buildEmpty() {
    return AppEmptyState(
      icon: CupertinoIcons.arrow_down_circle,
      title: l10n.queueEmpty,
      hint: l10n.queueEmptyHint,
    );
  }

  /// One-off lines explaining why the queue arrived full and idle.
  List<Widget> _buildNotices() {
    final notices = <({String text, IconData icon})>[
      if (state.restoredJobCount > 0)
        (
          text: l10n.queueRestoredNotice(state.restoredJobCount),
          icon: CupertinoIcons.clock,
        ),
      if (queue.isHalted)
        (text: l10n.queueHeldNotice, icon: CupertinoIcons.pause_circle),
    ];

    return <Widget>[
      for (final notice in notices)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppNotice(
            icon: notice.icon,
            message: notice.text,
            color: palette.warning,
          ),
        ),
    ];
  }

  Widget _buildJob({required QueueJob job, required List<QueueJob> jobs}) {
    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildJobHeader(job: job),
        if (job.status == QueueJobStatus.running) _buildJobProgress(job: job),
        if (job.error != null) _buildJobError(job: job),
        if (job.status == QueueJobStatus.completed) _buildJobResult(job: job),
        const SizedBox(height: AppSpacing.lg),
        _buildJobActions(job: job, jobs: jobs),
      ],
    );
    resultWidget = AppCard(child: resultWidget);
    resultWidget = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildJobHeader({required QueueJob job}) {
    final titleText = Text(
      job.title,
      overflow: TextOverflow.ellipsis,
      style: typography.headline.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );

    final Widget resultWidget = Row(
      children: <Widget>[
        Expanded(child: titleText),
        const SizedBox(width: AppSpacing.md),
        AppStatusPill(
          label: _statusLabel(status: job.status),
          color: _statusColor(status: job.status),
        ),
      ],
    );
    return resultWidget;
  }

  Widget _buildJobProgress({required QueueJob job}) {
    final progress = job.progress;
    if (progress == null) return _buildResolving();

    // Every byte in, digest still running: on a multi-gigabyte shard the
    // silence would otherwise read as a hang.
    final bool isVerifying = progress.file.fraction == 1.0;

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildProgressBar(progress: progress),
        const SizedBox(height: AppSpacing.md),
        _buildFileLine(progress: progress, isVerifying: isVerifying),
        const SizedBox(height: 2),
        _buildStatsLine(progress: progress),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildResolving() {
    final labelText = Text(
      l10n.statusResolving,
      style: typography.caption1.copyWith(color: palette.textSecondary),
    );

    Widget resultWidget = Row(
      children: <Widget>[
        const ProgressCircle(radius: 6),
        const SizedBox(width: AppSpacing.sm),
        labelText,
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: resultWidget,
    );
    return resultWidget;
  }

  /// The bar and the percentage read together: the bar for the shape of the
  /// progress, the number for whether it is still moving.
  Widget _buildProgressBar({required AddProgress progress}) {
    final double percent = (progress.fraction * 100).clamp(0, 100);

    final percentText = Text(
      '${percent.toStringAsFixed(0)}%',
      style: typography.caption1.copyWith(
        color: palette.textSecondary,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );

    final Widget resultWidget = Row(
      children: <Widget>[
        Expanded(
          child: ProgressBar(
            value: percent,
            height: AppSizes.progressBarHeight,
            trackColor: palette.accent,
            backgroundColor: palette.trackFill,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        percentText,
      ],
    );
    return resultWidget;
  }

  Widget _buildFileLine({
    required AddProgress progress,
    required bool isVerifying,
  }) {
    return Text(
      isVerifying
          ? l10n.statusVerifying
          : l10n.downloadFile(
              progress.fileName,
              progress.fileIndex + 1,
              progress.fileCount,
            ),
      overflow: TextOverflow.ellipsis,
      style: typography.caption1.copyWith(color: palette.textPrimary),
    );
  }

  /// Bytes, rate, ETA and connections on one line rather than two: they answer
  /// the same question, and stacking them made the card twice as tall for it.
  Widget _buildStatsLine({required AddProgress progress}) {
    final parts = <String>[
      l10n.downloadStats(
        formatBytes(bytes: progress.receivedBytes),
        formatBytes(bytes: progress.totalBytes),
        formatRate(bytesPerSecond: progress.file.bytesPerSecond),
        formatDuration(duration: progress.file.eta),
      ),
      l10n.downloadConnections(
        progress.file.activeConnections,
        progress.file.completedChunks,
        progress.file.totalChunks,
      ),
    ];

    return Text(
      parts.join(' · '),
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );
  }

  Widget _buildJobResult({required QueueJob job}) {
    final visible = job.linkedVisibleBytes;
    final cost = job.linkedCostBytes;
    if (visible == null || cost == null) return const SizedBox.shrink();

    Widget resultWidget = AppNotice(
      icon: CupertinoIcons.checkmark_circle,
      message: l10n.linkedResult(
        formatBytes(bytes: visible),
        formatBytes(bytes: cost),
      ),
      color: palette.success,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildJobError({required QueueJob job}) {
    Widget resultWidget = AppNotice(
      icon: CupertinoIcons.exclamationmark_triangle,
      message: job.error ?? '',
      color: palette.danger,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildJobActions({
    required QueueJob job,
    required List<QueueJob> jobs,
  }) {
    final int index = jobs.indexOf(job);
    final bool canReorder = !job.isFinished && jobs.length > 1;

    final Widget resultWidget = Row(
      children: <Widget>[
        ..._buildHoldActions(job: job),
        PushButton(
          controlSize: ControlSize.regular,
          secondary: true,
          onPressed: () => logic.removeJob(jobId: job.id),
          child: Text(l10n.removeFromQueueAction),
        ),
        const Spacer(),
        if (canReorder)
          ..._buildReorderActions(job: job, index: index, jobs: jobs),
      ],
    );
    return resultWidget;
  }

  List<Widget> _buildHoldActions({required QueueJob job}) {
    final bool isPausable = job.status == QueueJobStatus.running ||
        job.status == QueueJobStatus.queued;

    return <Widget>[
      if (isPausable)
        PushButton(
          controlSize: ControlSize.regular,
          secondary: true,
          onPressed: () => logic.pauseJob(jobId: job.id),
          child: Text(l10n.pauseAction),
        ),
      if (job.status == QueueJobStatus.paused)
        PushButton(
          controlSize: ControlSize.regular,
          onPressed: () => logic.resumeJob(jobId: job.id),
          child: Text(l10n.resumeAction),
        ),
      if (!job.isFinished) const SizedBox(width: AppSpacing.sm),
      if (!job.isFinished)
        PushButton(
          controlSize: ControlSize.regular,
          secondary: true,
          onPressed: () => logic.cancelJob(jobId: job.id),
          child: Text(l10n.cancelAction),
        ),
      if (!job.isFinished) const SizedBox(width: AppSpacing.sm),
    ];
  }

  List<Widget> _buildReorderActions({
    required QueueJob job,
    required int index,
    required List<QueueJob> jobs,
  }) {
    return <Widget>[
      MacosIconButton(
        icon: const MacosIcon(CupertinoIcons.chevron_up, size: 12),
        semanticLabel: l10n.moveUpAction,
        onPressed: index == 0 ? null : () => logic.moveJobUp(jobId: job.id),
      ),
      MacosIconButton(
        icon: const MacosIcon(CupertinoIcons.chevron_down, size: 12),
        semanticLabel: l10n.moveDownAction,
        onPressed: index == jobs.length - 1
            ? null
            : () => logic.moveJobDown(jobId: job.id),
      ),
    ];
  }

  String _statusLabel({required QueueJobStatus status}) {
    return switch (status) {
      QueueJobStatus.queued => l10n.jobStatusQueued,
      QueueJobStatus.running => l10n.jobStatusRunning,
      QueueJobStatus.paused => l10n.jobStatusPaused,
      QueueJobStatus.completed => l10n.jobStatusCompleted,
      QueueJobStatus.cancelled => l10n.jobStatusCancelled,
      QueueJobStatus.failed => l10n.jobStatusFailed,
    };
  }

  Color _statusColor({required QueueJobStatus status}) {
    return switch (status) {
      QueueJobStatus.running => palette.accent,
      QueueJobStatus.completed => palette.success,
      QueueJobStatus.failed => palette.danger,
      QueueJobStatus.paused => palette.warning,
      QueueJobStatus.queued => palette.neutral,
      QueueJobStatus.cancelled => palette.neutral,
    };
  }
}
