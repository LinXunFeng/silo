import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_section.dart';
import 'package:silo_app/page/library/state/library_state.dart';

/// The sidebar: four destinations, each with the number that matters to it.
///
/// The counts are the whole point of putting them here — how many models are
/// stored and how many jobs are waiting are the two questions asked most often,
/// and neither should cost a click.
class LibraryNavView extends StatefulWidget {
  const LibraryNavView({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  State<LibraryNavView> createState() => _LibraryNavViewState();
}

class _LibraryNavViewState extends State<LibraryNavView>
    with LibraryLogicConsumerMixin<LibraryNavView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  AppPalette get palette => AppPalette.of(context);

  MacosTypography get typography => MacosTheme.of(context).typography;

  int get storedCount => state.catalog.entries.length;

  int get queuedCount => logic.queue.jobs.where((job) => !job.isFinished).length;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.navigation,
      builder: (_) => _buildBody(),
    );
  }

  Widget _buildBody() {
    Widget resultWidget = SidebarItems(
      currentIndex: LibrarySection.values.indexOf(state.selectedSection),
      onChanged: _onSectionChanged,
      itemSize: SidebarItemSize.large,
      scrollController: widget.scrollController,
      items: <SidebarItem>[
        _buildItem(section: LibrarySection.discover),
        _buildItem(section: LibrarySection.library),
        _buildItem(section: LibrarySection.queue),
        _buildItem(section: LibrarySection.targets),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: resultWidget,
    );
    return resultWidget;
  }

  SidebarItem _buildItem({required LibrarySection section}) {
    return SidebarItem(
      leading: MacosIcon(_iconFor(section: section)),
      label: Text(_labelFor(section: section)),
      trailing: _buildBadge(section: section),
    );
  }

  /// Zero is left blank rather than shown: a row of noughts is noise, and an
  /// empty queue is already the default assumption.
  Widget? _buildBadge({required LibrarySection section}) {
    final int? count = _countFor(section: section);
    if (count == null || count == 0) return null;

    return Text(
      '$count',
      style: typography.caption1.copyWith(color: palette.textSecondary),
    );
  }

  int? _countFor({required LibrarySection section}) {
    return switch (section) {
      LibrarySection.library => storedCount,
      LibrarySection.queue => queuedCount,
      LibrarySection.discover => null,
      LibrarySection.targets => null,
    };
  }

  IconData _iconFor({required LibrarySection section}) {
    return switch (section) {
      LibrarySection.discover => CupertinoIcons.search,
      LibrarySection.library => CupertinoIcons.cube_box,
      LibrarySection.queue => CupertinoIcons.arrow_down_circle,
      LibrarySection.targets => CupertinoIcons.square_grid_2x2,
    };
  }

  String _labelFor({required LibrarySection section}) {
    return switch (section) {
      LibrarySection.discover => l10n.discoverTitle,
      LibrarySection.library => l10n.libraryTitle,
      LibrarySection.queue => l10n.queueTitle,
      LibrarySection.targets => l10n.targetsNavTitle,
    };
  }

  void _onSectionChanged(int index) {
    logic.selectSection(section: LibrarySection.values[index]);
  }
}
