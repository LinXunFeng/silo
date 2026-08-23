import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';

/// What an empty section says for itself.
///
/// A blank panel is indistinguishable from one that failed to load, so every
/// section that can be empty says so, and says what would fill it.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });

  final IconData icon;

  final String title;

  /// The action that would make this section non-empty.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typography = MacosTheme.of(context).typography;

    final iconWidget = MacosIcon(
      icon,
      size: 26,
      color: palette.neutral.withValues(alpha: 0.6),
    );

    final titleText = Text(
      title,
      textAlign: TextAlign.center,
      style: typography.body.copyWith(color: palette.textSecondary),
    );

    Widget resultWidget = Column(
      children: <Widget>[
        iconWidget,
        const SizedBox(height: AppSpacing.md),
        titleText,
        if (hint != null) _buildHint(context: context),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      child: resultWidget,
    );
    resultWidget = Center(child: resultWidget);
    return resultWidget;
  }

  Widget _buildHint({required BuildContext context}) {
    final palette = AppPalette.of(context);
    final typography = MacosTheme.of(context).typography;

    Widget resultWidget = Text(
      hint ?? '',
      textAlign: TextAlign.center,
      style: typography.caption1.copyWith(
        color: palette.neutral.withValues(alpha: 0.9),
      ),
    );
    resultWidget = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: resultWidget,
    );
    return resultWidget;
  }
}
