import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:get/get.dart';
import 'package:silo_app/common/setting/app_setting_store.dart';
import 'package:silo_app/common/theme/app_theme_mode.dart';

/// Holds the appearance choice for the whole window.
///
/// It sits above the page rather than inside it because `MacosApp` is what
/// consumes the answer, and that is the one widget the library page is a
/// descendant of.
class AppThemeLogic extends GetxController {
  AppThemeLogic({AppSettingStore store = const AppSettingStore()})
      : _store = store;

  final AppSettingStore _store;

  AppThemeMode themeMode = AppThemeMode.system;

  /// What `MacosApp` needs: the same choice in the framework's vocabulary.
  ThemeMode get resolvedThemeMode {
    return switch (themeMode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
  }

  @override
  void onInit() {
    super.onInit();
    unawaited(restoreThemeMode());
  }

  /// Reads the saved choice after the first frame.
  ///
  /// The window opens following the system and corrects itself a moment later
  /// if it was pinned. Blocking startup on a file read to avoid one repaint
  /// would be the worse trade.
  Future<void> restoreThemeMode() async {
    final name = await _store.readThemeMode();
    final restored = AppThemeMode.parse(name: name);
    if (restored == themeMode) return;
    themeMode = restored;
    update();
  }

  Future<void> selectThemeMode({required AppThemeMode mode}) async {
    if (themeMode == mode) return;
    themeMode = mode;
    update();
    await _store.writeThemeMode(name: mode.name);
  }
}
