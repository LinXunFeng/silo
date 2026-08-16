import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/color/color.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_link.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

class LibraryTargetsView extends StatefulWidget {
  const LibraryTargetsView({super.key});

  @override
  State<LibraryTargetsView> createState() => _LibraryTargetsViewState();
}

class _LibraryTargetsViewState extends State<LibraryTargetsView>
    with LibraryLogicConsumerMixin<LibraryTargetsView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

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
    final targetRows = <Widget>[
      for (final target in state.targets) _buildRow(target: target),
    ];

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.targetsTitle, style: typography.headline),
        const SizedBox(height: 6),
        ...targetRows,
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 20),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildRow({required DownloadTarget target}) {
    final isPresent = state.presentTargetIds.contains(target.id);

    Widget resultWidget = Row(
      children: <Widget>[
        MacosCheckbox(
          value: state.selectedTargetIds.contains(target.id),
          onChanged: (_) => logic.toggleTarget(targetId: target.id),
        ),
        const SizedBox(width: 8),
        Expanded(child: _buildLabel(target: target, isPresent: isPresent)),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildLabel({
    required DownloadTarget target,
    required bool isPresent,
  }) {
    final suffix = isPresent ? '' : ' · ${l10n.targetNotInstalled}';

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('${target.displayName}$suffix', style: typography.body),
        Text(
          target.root.path,
          style: typography.caption2
              .copyWith(color: AppColors.color8E8E93),
        ),
      ],
    );
    return resultWidget;
  }
}
