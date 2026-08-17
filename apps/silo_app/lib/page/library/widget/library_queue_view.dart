import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/color/color.dart';
import 'package:silo_app/common/format/byte_format.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_download.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

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

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildHeader(),
        const SizedBox(height: 8),
        if (jobs.isEmpty) _buildEmpty(),
        for (final job in jobs) _buildJob(job: job, jobs: jobs),
        _buildNotice(),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 20),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildHeader() {
    final Widget resultWidget = Row(
      children: <Widget>[
        Text(l10n.queueTitle, style: typography.headline),
        const SizedBox(width: 10),
        Expanded(child: _buildSummary()),
        ..._buildHeaderActions(),
      ],
    );
    return resultWidget;
  }

  Widget _buildSummary() {
    if (queue.pendingCount == 0) return const SizedBox.shrink();
    return Text(
      l10n.queueSummary(queue.pendingCount),
      style: typography.caption1.copyWith(color: AppColors.color8E8E93),
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
        controlSize: ControlSize.small,
        secondary: true,
        onPressed: anyFinished ? logic.clearFinishedJobs : null,
        child: Text(l10n.queueClearAction),
      ),
      const SizedBox(width: 6),
      PushButton(
        controlSize: ControlSize.small,
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
    return Text(
      l10n.queueEmpty,
      style: typography.caption1.copyWith(color: AppColors.color8E8E93),
    );
  }

  /// A one-off line explaining why the queue arrived full and idle.
  Widget _buildNotice() {
    final notices = <String>[
      if (state.restoredJobCount > 0)
        l10n.queueRestoredNotice(state.restoredJobCount),
      if (queue.isHalted) l10n.queueHeldNotice,
    ];
    if (notices.isEmpty) return const SizedBox.shrink();

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final notice in notices)
          Text(
            notice,
            style: typography.caption2
                .copyWith(color: AppColors.colorFB8C00),
          ),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildJob({required QueueJob job, required List<QueueJob> jobs}) {
    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildJobHeader(job: job),
        if (job.status == QueueJobStatus.running) _buildJobProgress(job: job),
        if (job.error != null) _buildJobError(job: job),
        if (job.status == QueueJobStatus.completed) _buildJobResult(job: job),
        const SizedBox(height: 8),
        _buildJobActions(job: job, jobs: jobs),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.all(12),
      child: resultWidget,
    );
    resultWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.color8E8E93.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: resultWidget,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildJobHeader({required QueueJob job}) {
    final Widget resultWidget = Row(
      children: <Widget>[
        Expanded(child: Text(job.title, style: typography.body)),
        const SizedBox(width: 8),
        Text(
          _statusLabel(status: job.status),
          style: typography.caption1
              .copyWith(color: _statusColor(status: job.status)),
        ),
      ],
    );
    return resultWidget;
  }

  Widget _buildJobProgress({required QueueJob job}) {
    final progress = job.progress;
    if (progress == null) {
      Widget resultWidget = Text(
        l10n.statusResolving,
        style: typography.caption1,
      );
      resultWidget = Padding(
        padding: const EdgeInsets.only(top: 6),
        child: resultWidget,
      );
      return resultWidget;
    }

    // Every byte in, digest still running: on a multi-gigabyte shard the
    // silence would otherwise read as a hang.
    final bool verifying = progress.file.fraction == 1.0;

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ProgressBar(value: (progress.fraction * 100).clamp(0, 100)),
        const SizedBox(height: 6),
        Text(
          verifying
              ? l10n.statusVerifying
              : l10n.downloadFile(
                  progress.fileName,
                  progress.fileIndex + 1,
                  progress.fileCount,
                ),
          style: typography.caption1,
        ),
        Text(
          l10n.downloadStats(
            formatBytes(bytes: progress.receivedBytes),
            formatBytes(bytes: progress.totalBytes),
            formatRate(bytesPerSecond: progress.file.bytesPerSecond),
            formatDuration(duration: progress.file.eta),
          ),
          style: typography.caption2
              .copyWith(color: AppColors.color8E8E93),
        ),
        Text(
          l10n.downloadConnections(
            progress.file.activeConnections,
            progress.file.completedChunks,
            progress.file.totalChunks,
          ),
          style: typography.caption2
              .copyWith(color: AppColors.color8E8E93),
        ),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildJobResult({required QueueJob job}) {
    final visible = job.linkedVisibleBytes;
    final cost = job.linkedCostBytes;
    if (visible == null || cost == null) return const SizedBox.shrink();

    Widget resultWidget = Text(
      l10n.linkedResult(
        formatBytes(bytes: visible),
        formatBytes(bytes: cost),
      ),
      style: typography.caption2.copyWith(color: AppColors.color43A047),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildJobError({required QueueJob job}) {
    Widget resultWidget = Text(
      job.error ?? '',
      style: typography.caption2.copyWith(color: AppColors.colorE53935),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 4),
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
        if (job.status == QueueJobStatus.running ||
            job.status == QueueJobStatus.queued)
          PushButton(
            controlSize: ControlSize.small,
            secondary: true,
            onPressed: () => logic.pauseJob(jobId: job.id),
            child: Text(l10n.pauseAction),
          ),
        if (job.status == QueueJobStatus.paused)
          PushButton(
            controlSize: ControlSize.small,
            onPressed: () => logic.resumeJob(jobId: job.id),
            child: Text(l10n.resumeAction),
          ),
        if (!job.isFinished) const SizedBox(width: 6),
        if (!job.isFinished)
          PushButton(
            controlSize: ControlSize.small,
            secondary: true,
            onPressed: () => logic.cancelJob(jobId: job.id),
            child: Text(l10n.cancelAction),
          ),
        const SizedBox(width: 6),
        PushButton(
          controlSize: ControlSize.small,
          secondary: true,
          onPressed: () => logic.removeJob(jobId: job.id),
          child: Text(l10n.removeFromQueueAction),
        ),
        if (canReorder) const Spacer(),
        if (canReorder)
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.chevron_up, size: 12),
            onPressed:
                index == 0 ? null : () => logic.moveJobUp(jobId: job.id),
          ),
        if (canReorder)
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.chevron_down, size: 12),
            onPressed: index == jobs.length - 1
                ? null
                : () => logic.moveJobDown(jobId: job.id),
          ),
      ],
    );
    return resultWidget;
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
      QueueJobStatus.running => AppColors.color1E88E5,
      QueueJobStatus.completed => AppColors.color43A047,
      QueueJobStatus.failed => AppColors.colorE53935,
      QueueJobStatus.paused => AppColors.colorFB8C00,
      QueueJobStatus.queued => AppColors.color8E8E93,
      QueueJobStatus.cancelled => AppColors.color8E8E93,
    };
  }
}
