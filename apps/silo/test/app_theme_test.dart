import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:silo_app/common/setting/app_setting_store.dart';
import 'package:silo_app/common/theme/app_theme_logic.dart';
import 'package:silo_app/common/theme/app_theme_mode.dart';

void main() {
  late Directory tempDir;
  late AppSettingStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('silo_app_settings');
    store = AppSettingStore(file: File('${tempDir.path}/app_settings.json'));
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('the appearance preference', () {
    test('is absent before anything is chosen', () async {
      expect(await store.readThemeMode(), isNull);
    });

    test('survives being written and read back', () async {
      await store.writeThemeMode(name: AppThemeMode.dark.name);

      expect(await store.readThemeMode(), 'dark');
    });

    test('keeps only the latest choice', () async {
      await store.writeThemeMode(name: AppThemeMode.dark.name);
      await store.writeThemeMode(name: AppThemeMode.light.name);

      expect(await store.readThemeMode(), 'light');
    });

    // A hand-edited or half-written file must not stop the window opening.
    test('reads as absent when the file is not valid JSON', () async {
      store.file.parent.createSync(recursive: true);
      store.file.writeAsStringSync('{ this is not json');

      expect(await store.readThemeMode(), isNull);
    });

    test('reads as absent when the file holds something else', () async {
      store.file.parent.createSync(recursive: true);
      store.file.writeAsStringSync('["dark"]');

      expect(await store.readThemeMode(), isNull);
    });
  });

  group('an unrecognised name', () {
    test('falls back to following the system', () {
      expect(AppThemeMode.parse(name: 'sepia'), AppThemeMode.system);
      expect(AppThemeMode.parse(name: null), AppThemeMode.system);
    });

    test('does not swallow the names that are recognised', () {
      expect(AppThemeMode.parse(name: 'light'), AppThemeMode.light);
      expect(AppThemeMode.parse(name: 'dark'), AppThemeMode.dark);
      expect(AppThemeMode.parse(name: 'system'), AppThemeMode.system);
    });
  });

  group('the appearance logic', () {
    test('starts on the system before anything is restored', () {
      final logic = AppThemeLogic(store: store);

      expect(logic.themeMode, AppThemeMode.system);
      expect(logic.resolvedThemeMode, ThemeMode.system);
    });

    test('maps each choice onto the framework mode', () async {
      final logic = AppThemeLogic(store: store);

      await logic.selectThemeMode(mode: AppThemeMode.light);
      expect(logic.resolvedThemeMode, ThemeMode.light);

      await logic.selectThemeMode(mode: AppThemeMode.dark);
      expect(logic.resolvedThemeMode, ThemeMode.dark);
    });

    test('writes the choice through to disk', () async {
      final logic = AppThemeLogic(store: store);

      await logic.selectThemeMode(mode: AppThemeMode.dark);

      expect(await store.readThemeMode(), 'dark');
    });

    // Reopening the window must not silently drop the choice back to system.
    test('restores what the last session chose', () async {
      await AppThemeLogic(store: store)
          .selectThemeMode(mode: AppThemeMode.light);

      final reopened = AppThemeLogic(store: store);
      await reopened.restoreThemeMode();

      expect(reopened.themeMode, AppThemeMode.light);
    });

    test('restores to the system when nothing was ever chosen', () async {
      final logic = AppThemeLogic(store: store);
      await logic.restoreThemeMode();

      expect(logic.themeMode, AppThemeMode.system);
    });
  });
}
