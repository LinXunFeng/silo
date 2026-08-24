import 'package:flutter/widgets.dart';

/// Colours are defined by value, named after that value, so a colour is never
/// silently reused for an unrelated purpose.
///
/// Which of these a surface actually uses is decided by [AppPalette], which
/// reads the window's brightness. Nothing here knows about light or dark.
class AppColors {
  const AppColors._();

  static const color000000 = Color(0xFF000000);
  static const colorFFFFFF = Color(0xFFFFFFFF);

  static const color1D1D1F = Color(0xFF1D1D1F);
  static const color6E6E73 = Color(0xFF6E6E73);
  static const colorF5F5F7 = Color(0xFFF5F5F7);
  static const colorFAFAFC = Color(0xFFFAFAFC);
  static const colorE5E5EA = Color(0xFFE5E5EA);

  static const color1C1C1E = Color(0xFF1C1C1E);
  static const color252528 = Color(0xFF252528);
  static const color2C2C2E = Color(0xFF2C2C2E);
  static const color3A3A3C = Color(0xFF3A3A3C);
  static const color98989D = Color(0xFF98989D);

  static const color34C759 = Color(0xFF34C759);
  static const color32D74B = Color(0xFF32D74B);
  static const colorFF9500 = Color(0xFFFF9500);
  static const colorFF9F0A = Color(0xFFFF9F0A);
  static const colorFF3B30 = Color(0xFFFF3B30);
  static const colorFF453A = Color(0xFFFF453A);
  static const color8E8E93 = Color(0xFF8E8E93);
}
