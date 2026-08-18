import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/color/color.dart';
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

  MacosTypography get typography => MacosTheme.of(context).typography;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.results,
      builder: (_) => _buildBody(),
    );
  }

  Widget _buildBody() {
    // Only shown for a keyword search; a precise reference goes straight to
    // the variant list and never populates this.
    if (state.searchResults.isEmpty && !state.includeAllFormats) {
      return const SizedBox.shrink();
    }

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildHeader(),
        const SizedBox(height: 6),
        if (state.searchResults.isEmpty) _buildEmpty(),
        for (final result in state.searchResults) _buildRow(result: result),
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
        Text(l10n.searchResultsTitle, style: typography.headline),
        const SizedBox(width: 12),
        Expanded(child: _buildAllFormatsToggle()),
      ],
    );
    return resultWidget;
  }

  Widget _buildAllFormatsToggle() {
    final Widget resultWidget = Row(
      children: <Widget>[
        MacosCheckbox(
          value: state.includeAllFormats,
          onChanged: (_) => logic.toggleIncludeAllFormats(),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            l10n.searchShowAll,
            style: typography.caption2
                .copyWith(color: AppColors.color8E8E93),
          ),
        ),
      ],
    );
    return resultWidget;
  }

  Widget _buildEmpty() {
    return Text(
      l10n.searchNoResults,
      style: typography.caption1.copyWith(color: AppColors.color8E8E93),
    );
  }

  Widget _buildRow({required MergedSearchResult result}) {
    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(result.ref.id, style: typography.body),
        const SizedBox(height: 2),
        Text(_detailFor(result: result), style: typography.caption2),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: resultWidget,
    );
    resultWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.color8E8E93.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: resultWidget,
    );
    resultWidget = GestureDetector(
      onTap: () => logic.openResult(result: result),
      child: resultWidget,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: resultWidget,
    );
    return resultWidget;
  }

  /// Formats, popularity, and which hubs carry it — that last part doubles as
  /// a speed hint, since a repo on ModelScope comes down far faster here.
  String _detailFor({required MergedSearchResult result}) {
    final parts = <String>[
      if (result.formats.isNotEmpty) result.formats.join(', '),
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
