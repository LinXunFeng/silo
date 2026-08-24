import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_search.dart';
import 'package:silo_app/page/library/state/library_state.dart';

/// One box that takes either a keyword or an exact `author/repo`.
///
/// It is the largest control in the window because it is the only one every
/// session starts with.
class LibrarySearchView extends StatefulWidget {
  const LibrarySearchView({super.key});

  @override
  State<LibrarySearchView> createState() => _LibrarySearchViewState();
}

class _LibrarySearchViewState extends State<LibrarySearchView>
    with LibraryLogicConsumerMixin<LibrarySearchView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  AppPalette get palette => AppPalette.of(context);

  MacosTypography get typography => MacosTheme.of(context).typography;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.search,
      builder: (_) => _buildBody(),
    );
  }

  Widget _buildBody() {
    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildField(),
        _buildStatusLine(),
      ],
    );
    return resultWidget;
  }

  /// The field sizes itself and the button follows.
  ///
  /// Pinning the field to a fixed height clipped the placeholder: a Chinese
  /// line box is taller than a Latin one, and the punctuation that sits on the
  /// baseline was the first thing to be cut off. So the height comes from the
  /// text's own metrics, and the button is stretched to match whatever that
  /// turns out to be.
  Widget _buildField() {
    Widget resultWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: _buildTextField()),
        const SizedBox(width: AppSpacing.sm),
        _buildSubmitButton(),
      ],
    );
    resultWidget = IntrinsicHeight(child: resultWidget);
    return resultWidget;
  }

  Widget _buildTextField() {
    return MacosTextField(
      controller: state.searchController,
      placeholder: l10n.searchPlaceholder,
      placeholderStyle: typography.body.copyWith(color: palette.neutral),
      style: typography.body.copyWith(color: palette.textPrimary),
      prefix: _buildFieldIcon(),
      clearButtonMode: OverlayVisibilityMode.editing,
      textAlignVertical: TextAlignVertical.center,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      focusedDecoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.accent, width: 2),
      ),
      onSubmitted: (_) => logic.submitQuery(),
    );
  }

  Widget _buildFieldIcon() {
    Widget resultWidget = MacosIcon(
      CupertinoIcons.search,
      size: 15,
      color: palette.neutral,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildSubmitButton() {
    return PushButton(
      controlSize: ControlSize.large,
      onPressed: state.isSearching ? null : logic.submitQuery,
      child: Text(l10n.searchAction),
    );
  }

  /// One line under the field, carrying whichever of three things is true:
  /// a lookup in flight, the reason the last one failed, or which mirrors
  /// turned out to carry the repository.
  Widget _buildStatusLine() {
    final message = _statusMessage;
    if (message == null) return const SizedBox(height: AppSpacing.md);

    Widget resultWidget = Row(
      children: <Widget>[
        if (state.isSearching) _buildSpinner(),
        Flexible(child: _buildStatusText(message: message)),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildSpinner() {
    Widget resultWidget = const ProgressCircle(radius: 6);
    resultWidget = Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildStatusText({required ({String text, bool isError}) message}) {
    return Text(
      message.text,
      style: typography.caption1.copyWith(
        color: message.isError ? palette.danger : palette.textSecondary,
      ),
    );
  }

  ({String text, bool isError})? get _statusMessage {
    if (state.isSearching) {
      return (text: l10n.searching, isError: false);
    }
    final error = state.errorMessage;
    if (error != null && state.variants.isEmpty) {
      return (text: error, isError: true);
    }
    if (state.availableSourceIds.isEmpty) return null;
    return (
      text: l10n.availableFrom(state.availableSourceIds.join(', ')),
      isError: false,
    );
  }
}
