import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';

/// A word about state, tinted by what that state means.
///
/// Colour alone would fail anyone who cannot separate the hues, so the pill
/// always carries the word too — the tint only makes it findable at a glance.
class AppStatusPill extends StatelessWidget {
  const AppStatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final typography = MacosTheme.of(context).typography;

    Widget resultWidget = Text(
      label,
      style: typography.caption1.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      child: resultWidget,
    );
    resultWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: resultWidget,
    );
    return resultWidget;
  }
}
