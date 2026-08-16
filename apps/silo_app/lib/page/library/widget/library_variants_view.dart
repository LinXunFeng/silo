import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/color/color.dart';
import 'package:silo_app/common/format/byte_format.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/header/library_header.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';
import 'package:silo_app/page/library/logic/library_logic_download.dart';
import 'package:silo_app/page/library/logic/library_logic_search.dart';
import 'package:silo_app/page/library/state/library_state.dart';
import 'package:silo_core/silo_core.dart';

class LibraryVariantsView extends StatefulWidget {
  const LibraryVariantsView({super.key});

  @override
  State<LibraryVariantsView> createState() => _LibraryVariantsViewState();
}

class _LibraryVariantsViewState extends State<LibraryVariantsView>
    with LibraryLogicConsumerMixin<LibraryVariantsView> {
  LibraryState get state => logic.state;

  AppLocalizations get l10n => AppLocalizations.of(context);

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
        _buildHeader(),
        const SizedBox(height: 6),
        ...variantRows,
        const SizedBox(height: 12),
        _buildDownloadButton(),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: 20),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildHeader() {
    return Text(l10n.variantsTitle, style: typography.headline);
  }

  Widget _buildRow({required ModelVariant variant}) {
    final isSelected = variant.name == state.selectedVariantName;

    Widget resultWidget = Row(
      children: <Widget>[
        Expanded(child: _buildRowLabel(variant: variant)),
        const SizedBox(width: 12),
        Text(
          formatBytes(bytes: variant.totalSize),
          style: typography.body,
        ),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: resultWidget,
    );
    resultWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.color1E88E5.withValues(alpha: 0.16)
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: resultWidget,
    );
    resultWidget = GestureDetector(
      onTap: () => logic.selectVariant(name: variant.name),
      child: resultWidget,
    );
    return resultWidget;
  }

  Widget _buildRowLabel({required ModelVariant variant}) {
    final detail = _detailFor(variant: variant);

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(variant.name, style: typography.body),
        if (detail != null)
          Text(
            detail,
            style: typography.caption2
                .copyWith(color: AppColors.color8E8E93),
          ),
      ],
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

  Widget _buildDownloadButton() {
    return PushButton(
      controlSize: ControlSize.large,
      onPressed: state.isDownloading ? null : logic.startDownload,
      child: Text(l10n.downloadAction),
    );
  }
}
