import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/widget/app_empty_state.dart';
import 'package:silo_app/common/widget/app_page_header.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_app/page/library/widget/library_results_view.dart';
import 'package:silo_app/page/library/widget/library_search_view.dart';
import 'package:silo_app/page/library/widget/library_variants_view.dart';

/// Finding something to download: the field, the hits, and the variants.
///
/// All three belong to one act, so they share a screen; everything else the
/// window does now lives behind its own sidebar entry.
class LibraryDiscoverView extends StatefulWidget {
  const LibraryDiscoverView({super.key});

  @override
  State<LibraryDiscoverView> createState() => _LibraryDiscoverViewState();
}

class _LibraryDiscoverViewState extends State<LibraryDiscoverView>
    with LibraryLogicConsumerMixin<LibraryDiscoverView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  /// True until the first lookup comes back.
  ///
  /// A lookup that matched nothing is not untouched — that case belongs to the
  /// results list, which can say so and offer the wider format filter.
  bool get isUntouched =>
      !state.hasLookedUp &&
      !state.isSearching &&
      state.errorMessage == null;

  @override
  Widget build(BuildContext context) {
    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildHeader(),
        const SizedBox(height: AppSpacing.xl),
        const LibrarySearchView(),
        _buildOutcome(),
      ],
    );
    return resultWidget;
  }

  Widget _buildHeader() {
    return AppPageHeader(
      title: l10n.discoverTitle,
      subtitle: l10n.discoverSubtitle,
    );
  }

  Widget _buildOutcome() {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.search,
      builder: (_) => _buildOutcomeBody(),
    );
  }

  Widget _buildOutcomeBody() {
    if (isUntouched) return _buildEmpty();

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        LibraryResultsView(),
        LibraryVariantsView(),
      ],
    );
    return resultWidget;
  }

  Widget _buildEmpty() {
    return AppEmptyState(
      icon: CupertinoIcons.search,
      title: l10n.discoverEmpty,
      hint: l10n.discoverEmptyHint,
    );
  }
}
