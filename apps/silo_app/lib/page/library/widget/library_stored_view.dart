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
import 'package:silo_app/common/widget/app_stat_tile.dart';
import 'package:silo_app/common/widget/app_status_pill.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_link.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

/// What is in the store, what it cost, and what dedup gave back.
class LibraryStoredView extends StatefulWidget {
  const LibraryStoredView({super.key});

  @override
  State<LibraryStoredView> createState() => _LibraryStoredViewState();
}

class _LibraryStoredViewState extends State<LibraryStoredView>
    with LibraryLogicConsumerMixin<LibraryStoredView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  AppPalette get palette => AppPalette.of(context);

  MacosTypography get typography => MacosTheme.of(context).typography;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.stored,
      builder: (_) => _buildBody(),
    );
  }

  Widget _buildBody() {
    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildHeader(),
        const SizedBox(height: AppSpacing.xl),
        _buildStats(),
        ..._buildNotices(),
        const SizedBox(height: AppSpacing.xl),
        _buildEntries(),
      ],
    );
    return resultWidget;
  }

  Widget _buildHeader() {
    return AppPageHeader(
      title: l10n.libraryTitle,
      subtitle: l10n.librarySubtitle,
    );
  }

  /// The four figures that describe the store, side by side.
  ///
  /// Saved and reclaimable only appear once they are non-zero: a permanent
  /// "0 B reclaimable" teaches the eye to skip the row that will one day
  /// matter.
  Widget _buildStats() {
    final storedTile = AppStatTile(
      value: '${state.catalog.entries.length}',
      label: l10n.statModels,
    );

    final onDiskTile = AppStatTile(
      value: formatBytes(bytes: state.storeBytes),
      label: l10n.statOnDisk,
    );

    Widget resultWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: storedTile),
        Expanded(child: onDiskTile),
        if (state.savedBytes > 0) Expanded(child: _buildSavedTile()),
        if (state.reclaimableBytes > 0)
          Expanded(child: _buildReclaimableTile()),
      ],
    );
    resultWidget = AppCard(child: resultWidget);
    return resultWidget;
  }

  Widget _buildSavedTile() {
    return AppStatTile(
      value: formatBytes(bytes: state.savedBytes),
      label: l10n.statSaved,
      valueColor: palette.success,
    );
  }

  Widget _buildReclaimableTile() {
    return AppStatTile(
      value: formatBytes(bytes: state.reclaimableBytes),
      label: l10n.statReclaimable,
      valueColor: palette.warning,
    );
  }

  /// Results of the last reclaim or unlink, which are otherwise invisible.
  List<Widget> _buildNotices() {
    final notices = <({String text, Color color, IconData icon})>[];

    final blobs = state.lastGcBlobs;
    final freed = state.lastGcFreedBytes;
    if (blobs != null && freed != null && blobs > 0) {
      notices.add((
        text: l10n.gcResult(formatBytes(bytes: freed), blobs),
        color: palette.success,
        icon: CupertinoIcons.checkmark_circle,
      ));
    }
    final retained = state.lastGcRetainedBytes;
    if (retained != null && retained > 0) {
      notices.add((
        text: l10n.gcRetained(formatBytes(bytes: retained)),
        color: palette.warning,
        icon: CupertinoIcons.exclamationmark_circle,
      ));
    }
    final skipped = state.lastUnlinkSkipped;
    if (skipped != null && skipped > 0) {
      notices.add((
        text: l10n.unlinkSkipped(skipped),
        color: palette.warning,
        icon: CupertinoIcons.exclamationmark_circle,
      ));
    }

    return <Widget>[
      for (final notice in notices)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: AppNotice(
            icon: notice.icon,
            message: notice.text,
            color: notice.color,
          ),
        ),
    ];
  }

  Widget _buildEntries() {
    if (state.catalog.entries.isEmpty) return _buildEmpty();

    final entryCards = <Widget>[
      for (final entry in state.catalog.entries) _buildEntry(entry: entry),
    ];

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entryCards,
    );
    return resultWidget;
  }

  Widget _buildEmpty() {
    return AppEmptyState(
      icon: CupertinoIcons.cube_box,
      title: l10n.libraryEmpty,
      hint: l10n.libraryEmptyHint,
    );
  }

  Widget _buildEntry({required CatalogEntry entry}) {
    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildEntryHeader(entry: entry),
        const SizedBox(height: AppSpacing.md),
        _buildEntryMeta(entry: entry),
        const SizedBox(height: AppSpacing.lg),
        _buildEntryActions(entry: entry),
      ],
    );
    resultWidget = AppCard(child: resultWidget);
    resultWidget = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildEntryHeader({required CatalogEntry entry}) {
    final repoText = Text(
      entry.ref.repo,
      overflow: TextOverflow.ellipsis,
      style: typography.headline.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );

    final authorText = Text(
      entry.ref.author,
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );

    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        repoText,
        const SizedBox(height: 2),
        authorText,
      ],
    );

    final Widget resultWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: titleColumn),
        const SizedBox(width: AppSpacing.md),
        _buildLinkPill(entry: entry),
      ],
    );
    return resultWidget;
  }

  Widget _buildLinkPill({required CatalogEntry entry}) {
    final targets = _targetsFor(entry: entry);
    if (targets.isEmpty) {
      return AppStatusPill(
        label: l10n.entryNotLinked,
        color: palette.neutral,
      );
    }
    return AppStatusPill(
      label: l10n.entryLinkedTo(targets.join(', ')),
      color: palette.success,
    );
  }

  Set<String> _targetsFor({required CatalogEntry entry}) {
    return state.catalog
        .linksFor(entry.key)
        .map((link) => link.targetId)
        .toSet();
  }

  Widget _buildEntryMeta({required CatalogEntry entry}) {
    final variantText = Text(
      '${entry.variant} · ${formatBytes(bytes: entry.totalSize)}',
      style: typography.body.copyWith(color: palette.textPrimary),
    );

    final sourceText = Text(
      l10n.entrySource(entry.sourceId, entry.revision),
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        variantText,
        const SizedBox(height: 2),
        sourceText,
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: resultWidget,
    );
    resultWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildEntryActions({required CatalogEntry entry}) {
    final Widget resultWidget = Row(
      children: <Widget>[
        PushButton(
          controlSize: ControlSize.regular,
          onPressed: () => logic.linkEntry(
            ref: entry.ref,
            variantName: entry.variant,
          ),
          child: Text(l10n.linkAction),
        ),
        const SizedBox(width: AppSpacing.sm),
        PushButton(
          controlSize: ControlSize.regular,
          secondary: true,
          onPressed: () => logic.unlinkEntry(
            ref: entry.ref,
            variantName: entry.variant,
          ),
          child: Text(l10n.unlinkAction),
        ),
        const Spacer(),
        PushButton(
          controlSize: ControlSize.regular,
          secondary: true,
          onPressed: () => logic.forgetEntry(
            ref: entry.ref,
            variantName: entry.variant,
          ),
          child: Text(l10n.removeAction),
        ),
      ],
    );
    return resultWidget;
  }
}
