import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_dimens.dart';
import 'package:silo_app/common/theme/app_palette.dart';

/// A tinted line explaining something the user did not do on purpose — a held
/// queue, a restored session, files a reclaim declined to touch.
///
/// It is a banner rather than yet another caption because these lines answer
/// "why is nothing happening", and a caption in a column of captions is exactly
/// where that answer gets missed.
class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;

  final String message;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typography = MacosTheme.of(context).typography;

    final messageText = Text(
      message,
      style: typography.caption1.copyWith(color: palette.textPrimary),
    );

    Widget resultWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MacosIcon(icon, size: 13, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: messageText),
      ],
    );
    resultWidget = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: resultWidget,
    );
    resultWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: resultWidget,
    );
    return resultWidget;
  }
}
