import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';
import 'package:silo_app/common/widget/app_card.dart';
import 'package:silo_app/common/widget/app_page_header.dart';
import 'package:silo_app/common/widget/app_status_pill.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_link.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

/// The tools a finished download gets hard-linked into.
///
/// The whole card toggles, not just the checkbox: the row already reads as one
/// choice, and a 14-pixel hit target for the only decision on the screen is a
/// needless act of precision.
class LibraryTargetsView extends StatefulWidget {
  const LibraryTargetsView({super.key});

  @override
  State<LibraryTargetsView> createState() => _LibraryTargetsViewState();
}

class _LibraryTargetsViewState extends State<LibraryTargetsView>
    with LibraryLogicConsumerMixin<LibraryTargetsView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  AppPalette get palette => AppPalette.of(context);

  MacosTypography get typography => MacosTheme.of(context).typography;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.targets,
      builder: (_) => _buildBody(),
    );
  }

  Widget _buildBody() {
    final targetCards = <Widget>[
      for (final target in state.targets) _buildRow(target: target),
    ];

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildHeader(),
        const SizedBox(height: AppSpacing.xl),
        ...targetCards,
      ],
    );
    return resultWidget;
  }

  Widget _buildHeader() {
    return AppPageHeader(
      title: l10n.targetsNavTitle,
      subtitle: l10n.targetsSubtitle,
    );
  }

  Widget _buildRow({required DownloadTarget target}) {
    final bool isSelected = state.selectedTargetIds.contains(target.id);

    Widget resultWidget = Row(
      children: <Widget>[
        _buildCheckbox(target: target, isSelected: isSelected),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: _buildLabel(target: target)),
      ],
    );
    resultWidget = AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      isSelected: isSelected,
      onTap: () => logic.toggleTarget(targetId: target.id),
      child: resultWidget,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: resultWidget,
    );
    return resultWidget;
  }

  /// The box reports the state; the card is what changes it.
  ///
  /// It keeps its enabled colours — a disabled checkbox would say the target
  /// cannot be picked — but takes no pointers, so a click on the box and a
  /// click beside it are the same single toggle rather than two competing ones.
  Widget _buildCheckbox({
    required DownloadTarget target,
    required bool isSelected,
  }) {
    Widget resultWidget = MacosCheckbox(
      value: isSelected,
      onChanged: (_) => logic.toggleTarget(targetId: target.id),
    );
    resultWidget = IgnorePointer(child: resultWidget);
    return resultWidget;
  }

  Widget _buildLabel({required DownloadTarget target}) {
    final bool isPresent = state.presentTargetIds.contains(target.id);

    final nameText = Text(
      target.displayName,
      style: typography.body.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );

    final pathText = Text(
      target.root.path,
      overflow: TextOverflow.ellipsis,
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            nameText,
            if (!isPresent) _buildAbsentPill(),
          ],
        ),
        const SizedBox(height: 2),
        pathText,
      ],
    );
    return resultWidget;
  }

  /// A tool that is not installed can still be selected — its directory is
  /// created on the first link — so this is a note, not a warning.
  Widget _buildAbsentPill() {
    Widget resultWidget = AppStatusPill(
      label: l10n.targetNotInstalled,
      color: palette.neutral,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: resultWidget,
    );
    return resultWidget;
  }
}
