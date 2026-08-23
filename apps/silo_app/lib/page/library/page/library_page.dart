import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';
import 'package:silo_app/common/theme/app_theme_logic.dart';
import 'package:silo_app/common/theme/app_theme_mode.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_link.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_app/page/library/widget/library_discover_view.dart';
import 'package:silo_app/page/library/widget/library_footer_view.dart';
import 'package:silo_app/page/library/widget/library_nav_view.dart';
import 'package:silo_app/page/library/widget/library_queue_view.dart';
import 'package:silo_app/page/library/widget/library_stored_view.dart';
import 'package:silo_app/page/library/widget/library_targets_view.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage>
    with LibraryLogicPutMixin<LibraryPage> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  AppPalette get palette => AppPalette.of(context);

  MacosTypography get typography => MacosTheme.of(context).typography;

  AppThemeLogic get themeLogic => Get.find<AppThemeLogic>();

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
      minWidth: AppSizes.sidebarMinWidth,
      startWidth: AppSizes.sidebarStartWidth,
      top: _buildBrand(),
      builder: (context, scrollController) => LibraryNavView(
        scrollController: scrollController,
      ),
      bottom: const LibraryFooterView(),
    );
  }

  /// The name and the promise, once, at the top of the window.
  ///
  /// The tagline used to sit above the search field, where it was re-read on
  /// every lookup. Here it introduces the app and then stays out of the way.
  Widget _buildBrand() {
    final nameText = Text(
      l10n.appTitle,
      style: typography.title2.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    );

    final taglineText = Text(
      l10n.tagline,
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        nameText,
        const SizedBox(height: 2),
        taglineText,
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: resultWidget,
    );
    return resultWidget;
  }

  /// Rebuilt on navigation because the toolbar title names the section, and a
  /// [ToolBar] is configuration rather than a widget — it cannot listen itself.
  Widget _buildScaffold() {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.navigation,
      builder: (_) => _buildAppearanceScope(),
    );
  }

  /// The appearance menu ticks the current choice, and that choice can change
  /// without the brightness changing — pinning the window to light while macOS
  /// is already light. Nothing else would rebuild the toolbar for that.
  Widget _buildAppearanceScope() {
    return GetBuilder<AppThemeLogic>(
      builder: (_) => _buildScaffoldBody(),
    );
  }

  Widget _buildScaffoldBody() {
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
      title: Text(_sectionTitle),
      titleWidth: 200,
      // Labelled, not bare icons. A trash can in a toolbar could mean delete
      // the selected model, or empty the library; it means neither, and
      // nothing on screen said so.
      actions: <ToolbarItem>[
        _buildAppearanceButton(),
        ToolBarIconButton(
          label: l10n.reclaimAction,
          tooltipMessage: l10n.reclaimTooltip,
          icon: const MacosIcon(CupertinoIcons.trash),
          onPressed: logic.confirmReclaimSpace,
          showLabel: true,
        ),
        ToolBarIconButton(
          label: l10n.refreshAction,
          tooltipMessage: l10n.refreshTooltip,
          icon: const MacosIcon(CupertinoIcons.refresh),
          onPressed: logic.loadStored,
          showLabel: true,
        ),
      ],
    );
  }

  /// A pulldown rather than a toggle: "follow the system" is a third state,
  /// and a two-way switch has nowhere to put it.
  ToolbarItem _buildAppearanceButton() {
    return ToolBarPullDownButton(
      label: l10n.appearanceAction,
      tooltipMessage: l10n.appearanceTooltip,
      icon: CupertinoIcons.circle_lefthalf_fill,
      items: <MacosPulldownMenuEntry>[
        for (final mode in AppThemeMode.values)
          _buildAppearanceItem(mode: mode),
      ],
    );
  }

  MacosPulldownMenuItem _buildAppearanceItem({required AppThemeMode mode}) {
    final label = _appearanceLabel(mode: mode);
    return MacosPulldownMenuItem(
      label: label,
      title: _buildAppearanceTitle(mode: mode, label: label),
      onTap: () => themeLogic.selectThemeMode(mode: mode),
    );
  }

  /// The tick is what makes the menu report the current choice; the blank of
  /// the same width in its place keeps every label on one left edge.
  Widget _buildAppearanceTitle({
    required AppThemeMode mode,
    required String label,
  }) {
    final bool isSelected = themeLogic.themeMode == mode;

    final Widget markWidget = isSelected
        ? MacosIcon(
            CupertinoIcons.checkmark,
            size: AppSizes.menuMarkWidth,
            color: palette.textPrimary,
          )
        : const SizedBox(width: AppSizes.menuMarkWidth);

    final Widget resultWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        markWidget,
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
    return resultWidget;
  }

  String _appearanceLabel({required AppThemeMode mode}) {
    return switch (mode) {
      AppThemeMode.system => l10n.appearanceSystem,
      AppThemeMode.light => l10n.appearanceLight,
      AppThemeMode.dark => l10n.appearanceDark,
    };
  }

  String get _sectionTitle {
    return switch (state.selectedSection) {
      LibrarySection.discover => l10n.discoverTitle,
      LibrarySection.library => l10n.libraryTitle,
      LibrarySection.queue => l10n.queueTitle,
      LibrarySection.targets => l10n.targetsNavTitle,
    };
  }

  /// Capped rather than stretched.
  ///
  /// Metadata lines run the width of their container, and on a maximised
  /// window an unbounded column turns every caption into a line the eye has to
  /// track back across.
  Widget _buildContent({required ScrollController scrollController}) {
    Widget resultWidget = _buildSection();
    resultWidget = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
      child: resultWidget,
    );
    resultWidget = Align(
      alignment: Alignment.topLeft,
      child: resultWidget,
    );
    resultWidget = SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxl,
      ),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildSection() {
    return switch (state.selectedSection) {
      LibrarySection.discover => const LibraryDiscoverView(),
      LibrarySection.library => const LibraryStoredView(),
      LibrarySection.queue => const LibraryQueueView(),
      LibrarySection.targets => const LibraryTargetsView(),
    };
  }
}
