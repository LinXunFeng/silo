import 'package:flutter/widgets.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';

/// The one surface the whole app is built out of.
///
/// Every grouping — a queued job, a stored model, a target — is the same card,
/// so the eye learns the shape once. Tappable cards answer the pointer; static
/// ones stay still, which is how a card says whether it does anything.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.isSelected = false,
    this.onTap,
  });

  final Widget child;

  final EdgeInsets padding;

  final bool isSelected;

  final VoidCallback? onTap;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _isHovered = false;

  AppPalette get palette => AppPalette.of(context);

  bool get isInteractive => widget.onTap != null;

  Color get fillColor {
    if (widget.isSelected) return palette.selectionFill;
    if (_isHovered && isInteractive) return palette.hoverFill;
    return palette.surface;
  }

  Color get borderColor {
    if (widget.isSelected) return palette.accent;
    return palette.border;
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
        boxShadow: palette.cardShadow,
      ),
      child: resultWidget,
    );
    if (!isInteractive) return resultWidget;

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
