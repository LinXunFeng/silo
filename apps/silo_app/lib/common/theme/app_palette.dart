import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/color/color.dart';

/// The one place a colour gets a job.
///
/// [AppColors] holds values; this resolves which value fills which role for the
/// window's current brightness. Widgets ask for a role — `surface`, `danger` —
/// and never for a hex, so the whole app follows the system theme without a
/// single `isDark` check scattered through the views.
class AppPalette {
  const AppPalette._({required this.isDark, required this.accent});

  factory AppPalette.of(BuildContext context) {
    final theme = MacosTheme.of(context);
    return AppPalette._(
      isDark: theme.brightness == Brightness.dark,
      accent: theme.primaryColor,
    );
  }

  final bool isDark;

  /// The system accent colour, whatever the user picked in System Settings —
  /// and the grey macOS substitutes when the window is not the active one.
  /// Taking it from the theme is what keeps a tinted pill agreeing with the
  /// native button beside it.
  final Color accent;

  /// The window's own background, behind every card.
  Color get canvas => isDark ? AppColors.color1C1C1E : AppColors.colorF5F5F7;

  /// A card sitting on [canvas].
  Color get surface => isDark ? AppColors.color2C2C2E : AppColors.colorFFFFFF;

  /// A block nested inside a card — a stat strip, a notice.
  Color get surfaceSunken =>
      isDark ? AppColors.color252528 : AppColors.colorFAFAFC;

  Color get border => isDark ? AppColors.color3A3A3C : AppColors.colorE5E5EA;

  Color get textPrimary =>
      isDark ? AppColors.colorF5F5F7 : AppColors.color1D1D1F;

  Color get textSecondary =>
      isDark ? AppColors.color98989D : AppColors.color6E6E73;

  Color get success => isDark ? AppColors.color32D74B : AppColors.color34C759;

  Color get warning => isDark ? AppColors.colorFF9F0A : AppColors.colorFF9500;

  Color get danger => isDark ? AppColors.colorFF453A : AppColors.colorFF3B30;

  Color get neutral => AppColors.color8E8E93;

  /// The wash a row takes on under the pointer.
  Color get hoverFill => neutral.withValues(alpha: isDark ? 0.14 : 0.08);

  /// The wash a selected row keeps, tinted so selection reads as a state
  /// rather than as a second pointer.
  Color get selectionFill => accent.withValues(alpha: isDark ? 0.22 : 0.12);

  /// Track behind a progress bar, and the ground of a status pill.
  Color get trackFill => neutral.withValues(alpha: isDark ? 0.22 : 0.16);

  /// Shadows are what separate a card from the canvas without a heavy border.
  /// Dark mode drops them: on a near-black canvas they only muddy the edge.
  List<BoxShadow> get cardShadow {
    if (isDark) return const <BoxShadow>[];
    return <BoxShadow>[
      BoxShadow(
        color: AppColors.color000000.withValues(alpha: 0.05),
        blurRadius: 8,
        offset: const Offset(0, 1),
      ),
    ];
  }
}
