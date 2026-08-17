import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/color/color.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_link.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_app/page/library/widget/library_queue_view.dart';
import 'package:silo_app/page/library/widget/library_search_view.dart';
import 'package:silo_app/page/library/widget/library_stored_view.dart';
import 'package:silo_app/page/library/widget/library_targets_view.dart';
import 'package:silo_app/page/library/widget/library_variants_view.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage>
    with LibraryLogicPutMixin<LibraryPage> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  @override
  LibraryLogic initLogic() => LibraryLogic();

  /// Only the page root assigns an id, so the logic is disposed with it.
  @override
  bool assignId() => true;

  @override
  Widget buildBody(BuildContext context) {
    state.rootContext = context;

    return MacosWindow(
      sidebar: _buildSidebar(),
      child: _buildScaffold(),
    );
  }

  Sidebar _buildSidebar() {
    return Sidebar(
      minWidth: 260,
      startWidth: 300,
      top: _buildSidebarTop(),
      builder: (context, scrollController) => const LibraryStoredView(),
    );
  }

  Widget _buildSidebarTop() {
    Widget resultWidget = Text(
      l10n.libraryTitle,
      style: MacosTheme.of(context).typography.headline,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildScaffold() {
    return MacosScaffold(
      toolBar: _buildToolBar(),
      children: <Widget>[
        ContentArea(
          builder: (context, scrollController) => _buildContent(
            scrollController: scrollController,
          ),
        ),
      ],
    );
  }

  ToolBar _buildToolBar() {
    return ToolBar(
      title: Text(l10n.appTitle),
      titleWidth: 160,
      actions: <ToolbarItem>[
        ToolBarIconButton(
          label: l10n.reclaimAction,
          icon: const MacosIcon(CupertinoIcons.trash),
          onPressed: logic.reclaimSpace,
          showLabel: false,
        ),
        ToolBarIconButton(
          label: l10n.refreshAction,
          icon: const MacosIcon(CupertinoIcons.refresh),
          onPressed: logic.loadStored,
          showLabel: false,
        ),
      ],
    );
  }

  Widget _buildContent({required ScrollController scrollController}) {
    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildTagline(),
        const SizedBox(height: 16),
        const LibrarySearchView(),
        // Above the variant list on purpose: work in flight is the most
        // important thing on screen, and a long list of quantisations would
        // otherwise push it below the fold exactly when it matters.
        const LibraryQueueView(),
        const LibraryTargetsView(),
        const LibraryVariantsView(),
      ],
    );
    resultWidget = SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildTagline() {
    return Text(
      l10n.tagline,
      style: MacosTheme.of(context).typography.title3.copyWith(
            color: AppColors.color8E8E93,
          ),
    );
  }
}
