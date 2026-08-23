import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/format/byte_format.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/state/library_state.dart';

/// The store's size, pinned to the bottom of the sidebar.
///
/// It is the one figure worth seeing from every section — the whole point of
/// the app is that this number stays smaller than the sum of its parts.
class LibraryFooterView extends StatefulWidget {
  const LibraryFooterView({super.key});

  @override
  State<LibraryFooterView> createState() => _LibraryFooterViewState();
}

class _LibraryFooterViewState extends State<LibraryFooterView>
    with LibraryLogicConsumerMixin<LibraryFooterView> {
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
    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildSummary(),
        if (state.savedBytes > 0) _buildSaved(),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildSummary() {
    return Text(
      l10n.librarySummary(
        state.catalog.entries.length,
        formatBytes(bytes: state.storeBytes),
      ),
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );
  }

  Widget _buildSaved() {
    Widget resultWidget = Text(
      l10n.librarySaved(formatBytes(bytes: state.savedBytes)),
      style: typography.caption2.copyWith(color: palette.success),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: resultWidget,
    );
    return resultWidget;
  }
}
