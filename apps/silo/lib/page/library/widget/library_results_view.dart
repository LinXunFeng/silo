import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';
import 'package:silo_app/common/widget/app_card.dart';
import 'package:silo_app/common/widget/app_section_header.dart';
import 'package:silo_app/common/widget/app_status_pill.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_search.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

class LibraryResultsView extends StatefulWidget {
  const LibraryResultsView({super.key});

  @override
  State<LibraryResultsView> createState() => _LibraryResultsViewState();
}

class _LibraryResultsViewState extends State<LibraryResultsView>
    with LibraryLogicConsumerMixin<LibraryResultsView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  AppPalette get palette => AppPalette.of(context);

  MacosTypography get typography => MacosTheme.of(context).typography;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.results,
      builder: (_) => _buildBody(),
    );
  }

  /// Only shown for a keyword search; a precise reference goes straight to the
  /// variant list and never populates this.
  bool get isKeywordLookup =>
      state.hasLookedUp && state.inspectedRef == null;

  Widget _buildBody() {
    if (!isKeywordLookup) return const SizedBox.shrink();

    final resultCards = <Widget>[
      for (final result in state.searchResults) _buildRow(result: result),
    ];

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildHeader(),
        if (state.searchResults.isEmpty) _buildEmpty(),
        ...resultCards,
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildHeader() {
    return AppSectionHeader(
      title: l10n.searchResultsTitle,
      caption: state.searchResults.isEmpty
          ? null
          : '${state.searchResults.length}',
      actions: <Widget>[_buildAllFormatsToggle()],
    );
  }

  Widget _buildAllFormatsToggle() {
    final labelText = Text(
      l10n.searchShowAll,
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );

    final Widget resultWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MacosCheckbox(
          value: state.includeAllFormats,
          onChanged: (_) => logic.toggleIncludeAllFormats(),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: labelText),
      ],
    );
    return resultWidget;
  }

  Widget _buildEmpty() {
    return Text(
      l10n.searchNoResults,
      style: typography.body.copyWith(color: palette.textSecondary),
    );
  }

  Widget _buildRow({required MergedSearchResult result}) {
    Widget resultWidget = Row(
      children: <Widget>[
        Expanded(child: _buildLabel(result: result)),
        const SizedBox(width: AppSpacing.md),
        MacosIcon(
          CupertinoIcons.chevron_right,
          size: 13,
          color: palette.neutral,
        ),
      ],
    );
    resultWidget = AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      onTap: () => logic.openResult(result: result),
      child: resultWidget,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildLabel({required MergedSearchResult result}) {
    final idText = Text(
      result.ref.id,
      overflow: TextOverflow.ellipsis,
      style: typography.body.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );

    final detailText = Text(
      _detailFor(result: result),
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(child: idText),
            ..._buildFormatPills(result: result),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        detailText,
      ],
    );
    return resultWidget;
  }

  /// The format is what decides whether a local runner can load the repository
  /// at all, so it is a pill rather than another word in the metadata line.
  List<Widget> _buildFormatPills({required MergedSearchResult result}) {
    return <Widget>[
      for (final format in result.formats)
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          child: AppStatusPill(label: format, color: palette.accent),
        ),
    ];
  }

  /// Popularity, and which hubs carry it — that last part doubles as a speed
  /// hint, since a repo on ModelScope comes down far faster here.
  String _detailFor({required MergedSearchResult result}) {
    final parts = <String>[
      l10n.resultDownloads(_compact(result.downloads)),
      l10n.resultOnSources(result.sourceIds.join(', ')),
    ];
    return parts.join(' · ');
  }

  String _compact(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }
}
