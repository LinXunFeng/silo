import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/color/color.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_search.dart';
import 'package:silo_app/page/library/state/library_state.dart';

class LibrarySearchView extends StatefulWidget {
  const LibrarySearchView({super.key});

  @override
  State<LibrarySearchView> createState() => _LibrarySearchViewState();
}

class _LibrarySearchViewState extends State<LibrarySearchView>
    with LibraryLogicConsumerMixin<LibrarySearchView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

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

  Widget _buildField() {
    final Widget resultWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: _buildTextField()),
        const SizedBox(width: 8),
        _buildSubmitButton(),
      ],
    );
    return resultWidget;
  }

  Widget _buildTextField() {
    return MacosTextField(
      controller: state.searchController,
      placeholder: l10n.searchPlaceholder,
      onSubmitted: (_) => logic.submitQuery(),
    );
  }

  Widget _buildSubmitButton() {
    return PushButton(
      controlSize: ControlSize.large,
      onPressed: state.isSearching ? null : logic.submitQuery,
      child: Text(l10n.searchAction),
    );
  }

  Widget _buildStatusLine() {
    final message = _statusMessage;
    if (message == null) return const SizedBox(height: 12);

    Widget resultWidget = Text(
      message.text,
      style: MacosTheme.of(context).typography.caption1.copyWith(
            color: message.isError
                ? AppColors.colorE53935
                : AppColors.color8E8E93,
          ),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: resultWidget,
    );
    return resultWidget;
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
