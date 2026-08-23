import 'package:flutter/widgets.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';

/// A row inside a card that can be picked — a quantisation, a mirror.
///
/// Lighter than [AppCard] on purpose: these rows belong to one list and read as
/// a set, so only the pointer and the selection tint separate them, never a
/// border each.
class AppSelectableRow extends StatefulWidget {
  const AppSelectableRow({
    super.key,
    required this.child,
    required this.isSelected,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
  });

  final Widget child;

  final bool isSelected;

  final VoidCallback onTap;

  final EdgeInsets padding;

  @override
  State<AppSelectableRow> createState() => _AppSelectableRowState();
}

class _AppSelectableRowState extends State<AppSelectableRow> {
  bool _isHovered = false;

  AppPalette get palette => AppPalette.of(context);

  Color? get fillColor {
    if (widget.isSelected) return palette.selectionFill;
    if (_isHovered) return palette.hoverFill;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Widget resultWidget = Padding(
      padding: widget.padding,
      child: widget.child,
    );
    resultWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: resultWidget,
    );
    resultWidget = GestureDetector(
      onTap: widget.onTap,
      child: resultWidget,
    );
    resultWidget = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(isHovered: true),
      onExit: (_) => _setHovered(isHovered: false),
      child: resultWidget,
    );
    return resultWidget;
  }

  void _setHovered({required bool isHovered}) {
    if (_isHovered == isHovered) return;
    setState(() => _isHovered = isHovered);
  }
}
