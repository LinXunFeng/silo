import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';

/// One number, and the word that says what it counts.
///
/// The figure leads and the label follows, because the numbers are what a
/// glance is after — how much is stored, how much dedup gave back.
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;

  final String label;

  /// Set when the figure itself carries a meaning — space saved, space still
  /// waiting to be reclaimed.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typography = MacosTheme.of(context).typography;

    final valueText = Text(
      value,
      style: typography.title2.copyWith(
        color: valueColor ?? palette.textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    );

    final labelText = Text(
      label,
      style: typography.caption2.copyWith(color: palette.textSecondary),
    );

    final Widget resultWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        valueText,
        const SizedBox(height: AppSpacing.xs),
        labelText,
      ],
    );
    return resultWidget;
  }
}
