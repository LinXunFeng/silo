import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/color/color.dart';
import 'package:silo_app/common/format/byte_format.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_link.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

class LibraryStoredView extends StatefulWidget {
  const LibraryStoredView({super.key});

  @override
  State<LibraryStoredView> createState() => _LibraryStoredViewState();
}

class _LibraryStoredViewState extends State<LibraryStoredView>
    with LibraryLogicConsumerMixin<LibraryStoredView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

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
    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildSummary(),
        const SizedBox(height: 10),
        _buildEntries(),
      ],
    );
    resultWidget = SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildSummary() {
    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.librarySummary(
            state.catalog.entries.length,
            formatBytes(bytes: state.storeBytes),
          ),
          style: typography.caption1,
        ),
        if (state.savedBytes > 0)
          Text(
            l10n.librarySaved(formatBytes(bytes: state.savedBytes)),
            style: typography.caption2
                .copyWith(color: AppColors.color43A047),
          ),
        if (state.reclaimableBytes > 0)
          Text(
            l10n.libraryReclaimable(
              formatBytes(bytes: state.reclaimableBytes),
            ),
            style: typography.caption2
                .copyWith(color: AppColors.colorFB8C00),
          ),
      ],
    );
    return resultWidget;
  }

  Widget _buildEntries() {
    if (state.catalog.entries.isEmpty) {
      return Text(
        l10n.libraryEmpty,
        style: typography.caption1
            .copyWith(color: AppColors.color8E8E93),
      );
    }

    final entryRows = <Widget>[
      for (final entry in state.catalog.entries) _buildEntry(entry: entry),
    ];

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entryRows,
    );
    return resultWidget;
  }

  Widget _buildEntry({required CatalogEntry entry}) {
    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(entry.ref.repo, style: typography.body),
        Text(
          entry.ref.author,
          style: typography.caption2
              .copyWith(color: AppColors.color8E8E93),
        ),
        const SizedBox(height: 4),
        Text(
          '${entry.variant} · ${formatBytes(bytes: entry.totalSize)}',
          style: typography.caption1,
        ),
        Text(
          l10n.entrySource(entry.sourceId, entry.revision),
          style: typography.caption2
              .copyWith(color: AppColors.color8E8E93),
        ),
        Text(_linkLabel(entry: entry), style: typography.caption2),
        const SizedBox(height: 6),
        _buildEntryActions(entry: entry),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.all(10),
      child: resultWidget,
    );
    resultWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.color8E8E93.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: resultWidget,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: resultWidget,
    );
    return resultWidget;
  }

  String _linkLabel({required CatalogEntry entry}) {
    final targets = state.catalog
        .linksFor(entry.key)
        .map((link) => link.targetId)
        .toSet();
    if (targets.isEmpty) return l10n.entryNotLinked;
    return l10n.entryLinkedTo(targets.join(', '));
  }

  Widget _buildEntryActions({required CatalogEntry entry}) {
    final Widget resultWidget = Row(
      children: <Widget>[
        PushButton(
          controlSize: ControlSize.small,
          onPressed: () => logic.linkEntry(
            ref: entry.ref,
            variantName: entry.variant,
          ),
          child: Text(l10n.linkAction),
        ),
        const SizedBox(width: 6),
        PushButton(
          controlSize: ControlSize.small,
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
