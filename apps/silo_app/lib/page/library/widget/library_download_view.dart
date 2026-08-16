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

class LibraryDownloadView extends StatefulWidget {
  const LibraryDownloadView({super.key});

  @override
  State<LibraryDownloadView> createState() => _LibraryDownloadViewState();
}

class _LibraryDownloadViewState extends State<LibraryDownloadView>
    with LibraryLogicConsumerMixin<LibraryDownloadView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  MacosTypography get typography => MacosTheme.of(context).typography;

  AddProgress? get progress => state.progress;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.download,
      builder: (_) => _buildBody(),
    );
  }

  Widget _buildBody() {
    if (state.status == LibraryStatus.idle) return const SizedBox.shrink();

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildTitle(),
        const SizedBox(height: 8),
        _buildProgressBar(),
        const SizedBox(height: 8),
        _buildStats(),
        _buildDetail(),
        const SizedBox(height: 12),
        _buildActions(),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.all(14),
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
      padding: const EdgeInsets.only(top: 20),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildTitle() {
    return Text(_titleText, style: typography.headline);
  }

  String get _titleText {
    final ref = state.activeRef;
    switch (state.status) {
      case LibraryStatus.resolving:
        return l10n.statusResolving;
      case LibraryStatus.verifying:
        return l10n.statusVerifying;
      case LibraryStatus.paused:
        return l10n.statusPaused;
      case LibraryStatus.cancelled:
        return l10n.statusCancelled;
      case LibraryStatus.done:
        return l10n.statusDone(ref?.id ?? '');
      case LibraryStatus.failed:
        return state.errorMessage ?? '';
      case LibraryStatus.downloading:
      case LibraryStatus.idle:
        return l10n.downloadTitle;
    }
  }

  Widget _buildProgressBar() {
    final value = progress?.fraction ?? 0;
    return ProgressBar(value: (value * 100).clamp(0, 100));
  }

  Widget _buildStats() {
    final current = progress;
    if (current == null) return const SizedBox.shrink();

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.downloadFile(
            current.fileName,
            current.fileIndex + 1,
            current.fileCount,
          ),
          style: typography.body,
        ),
        const SizedBox(height: 2),
        Text(_statsText(progress: current), style: typography.caption1),
        Text(
          l10n.downloadConnections(
            current.file.activeConnections,
            current.file.completedChunks,
            current.file.totalChunks,
          ),
          style: typography.caption2
              .copyWith(color: AppColors.color8E8E93),
        ),
      ],
    );
    return resultWidget;
  }

  String _statsText({required AddProgress progress}) {
    return l10n.downloadStats(
      formatBytes(bytes: progress.receivedBytes),
      formatBytes(bytes: progress.totalBytes),
      formatRate(bytesPerSecond: progress.file.bytesPerSecond),
      formatDuration(duration: progress.file.eta),
    );
  }

  Widget _buildDetail() {
    final detail = state.statusDetail ?? _linkSummary;
    if (detail == null) return const SizedBox.shrink();

    Widget resultWidget = Text(
      detail,
      style: typography.caption2.copyWith(color: AppColors.color8E8E93),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: resultWidget,
    );
    return resultWidget;
  }

  /// After a link, say plainly what it cost — zero, when hard links worked.
  String? get _linkSummary {
    if (state.status != LibraryStatus.done) return null;
    final visible = state.lastLinkVisibleBytes;
    final cost = state.lastLinkCostBytes;
    if (visible == null || cost == null) return null;
    return l10n.linkedResult(
      formatBytes(bytes: visible),
      formatBytes(bytes: cost),
    );
  }

  Widget _buildActions() {
    final Widget resultWidget = Row(
      children: <Widget>[
        if (state.canPause)
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: logic.pauseDownload,
            child: Text(l10n.pauseAction),
          ),
        if (state.status == LibraryStatus.paused)
          PushButton(
            controlSize: ControlSize.regular,
            onPressed: logic.resumeDownload,
            child: Text(l10n.resumeAction),
          ),
        if (state.isDownloading) const SizedBox(width: 8),
        if (state.isDownloading)
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: logic.cancelDownload,
            child: Text(l10n.cancelAction),
          ),
      ],
    );
    return resultWidget;
  }
}
