import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/format/byte_format.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';
import 'package:silo_app/common/widget/app_card.dart';
import 'package:silo_app/common/widget/app_section_header.dart';
import 'package:silo_app/common/widget/app_selectable_row.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_download.dart';
import 'package:silo_app/page/library/logic/library_logic_search.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

/// The quantisations a repository offers, as one pickable list.
///
/// They sit in a single card rather than a card each: they are alternatives,
/// not items, and separate cards would read as things you could take several of.
class LibraryVariantsView extends StatefulWidget {
  const LibraryVariantsView({super.key});

  @override
  State<LibraryVariantsView> createState() => _LibraryVariantsViewState();
}

class _LibraryVariantsViewState extends State<LibraryVariantsView>
    with LibraryLogicConsumerMixin<LibraryVariantsView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

  AppPalette get palette => AppPalette.of(context);

  MacosTypography get typography => MacosTheme.of(context).typography;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.variants,
      builder: (_) => _buildBody(),
    );
  }

  Widget _buildBody() {
    if (state.variants.isEmpty) return const SizedBox.shrink();

    final variantRows = <Widget>[
      for (final variant in state.variants) _buildRow(variant: variant),
    ];

    Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...variantRows,
        _buildDivider(),
        _buildFooter(),
      ],
    );
    resultWidget = AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: resultWidget,
    );
    resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildHeader(),
        resultWidget,
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildHeader() {
    return AppSectionHeader(
      title: l10n.variantsTitle,
      caption: state.inspectedRef?.id,
    );
  }

  Widget _buildDivider() {
    Widget resultWidget = Container(
      height: 1,
      color: palette.border,
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildRow({required ModelVariant variant}) {
    final bool isSelected = variant.name == state.selectedVariantName;

    final sizeText = Text(
      formatBytes(bytes: variant.totalSize),
      style: typography.body.copyWith(
        color: isSelected ? palette.textPrimary : palette.textSecondary,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );

    Widget resultWidget = Row(
      children: <Widget>[
        Expanded(child: _buildRowLabel(variant: variant)),
        const SizedBox(width: AppSpacing.md),
        sizeText,
      ],
    );
    resultWidget = AppSelectableRow(
      isSelected: isSelected,
      onTap: () => logic.selectVariant(name: variant.name),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildRowLabel({required ModelVariant variant}) {
    final detail = _detailFor(variant: variant);

    final nameText = Text(
      variant.name,
      style: typography.body.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w500,
      ),
    );

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        nameText,
        if (detail != null) _buildDetail(detail: detail),
      ],
    );
    return resultWidget;
  }

  Widget _buildDetail({required String detail}) {
    Widget resultWidget = Text(
      detail,
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: resultWidget,
    );
    return resultWidget;
  }

  /// Companions mean different things per format: a projector a vision GGUF
  /// cannot see without, or the config and tokenizer set a safetensors model
  /// will not load without.
  String? _detailFor({required ModelVariant variant}) {
    final parts = <String>[];
    if (variant.isSharded) {
      parts.add(l10n.variantShards(variant.parts.length));
    }
    if (variant.companions.isNotEmpty) {
      parts.add(
        variant.format == ModelFormat.gguf
            ? l10n.variantProjector(variant.companions.length)
            : l10n.variantSupportFiles(variant.companions.length),
      );
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Says where the download will land before it is queued.
  ///
  /// Targets are chosen on another screen now, so without this line the queue
  /// button would be a decision made with half the information off-screen.
  Widget _buildFooter() {
    return GetBuilder<LibraryLogic>(
      tag: logicTag,
      id: LibraryUpdateType.targets,
      builder: (_) => _buildFooterBody(),
    );
  }

  Widget _buildFooterBody() {
    final bool hasTarget = state.selectedTargetIds.isNotEmpty;

    final summaryText = Text(
      hasTarget
          ? l10n.targetsSelected(_selectedTargetNames)
          : l10n.targetsNoneSelected,
      style: typography.caption1.copyWith(
        color: hasTarget ? palette.textSecondary : palette.warning,
      ),
    );

    Widget resultWidget = Row(
      children: <Widget>[
        Expanded(child: summaryText),
        const SizedBox(width: AppSpacing.md),
        _buildQueueButton(),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: resultWidget,
    );
    return resultWidget;
  }

  String get _selectedTargetNames {
    final names = <String>[
      for (final target in state.targets)
        if (state.selectedTargetIds.contains(target.id)) target.displayName,
    ];
    return names.join(', ');
  }

  /// Never disabled: queueing a second model while the first transfers is the
  /// point of having a queue.
  Widget _buildQueueButton() {
    return PushButton(
      controlSize: ControlSize.large,
      onPressed: logic.enqueueSelected,
      child: Text(l10n.queueAddAction),
    );
  }
}
