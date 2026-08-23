import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/color/color.dart';

/// Adjusts the theme macos_ui built, rather than replacing it.
///
/// [MacosApp] only fills in the system accent colour and whether the window is
/// the active one when it builds the theme itself — hand it a finished
/// [MacosThemeData] and both stay null forever. Native controls read those:
/// a checked [MacosCheckbox] with `isMainWindow` null paints its inactive
/// white face straight over the tick, so the box looks empty while everything
/// around it says it is selected.
///
/// So the base theme stays macos_ui's, and only the two colours this app has
/// an opinion about are changed, below the app and above the window.
class AppThemeScope extends StatelessWidget {
  const AppThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final Widget resultWidget = MacosTheme(
      data: theme.copyWith(
        // Dark mode only really needs this: macos_ui's near-black canvas sits
        // a shade off the card colour, which leaves every card edge guesswork.
        canvasColor:
            isDark ? AppColors.color1C1C1E : AppColors.colorF5F5F7,
        dividerColor:
            isDark ? AppColors.color3A3A3C : AppColors.colorE5E5EA,
      ),
      child: child,
    );
    return resultWidget;
  }
}
