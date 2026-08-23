import 'dart:convert';
import 'dart:io';

import 'package:silo_core/silo_core.dart';

/// The window's own preferences, kept as one small JSON file next to the
/// library at `~/.silo`.
///
/// Deliberately not the macOS defaults database: the CLI and the app share a
/// home directory already, and a preference you can read with `cat` is one you
/// can also delete when it goes wrong.
class AppSettingStore {
  /// [file] is only passed by tests; the app always uses the shared home.
  const AppSettingStore({File? file}) : _file = file;

  static const String _themeModeKey = 'themeMode';

  final File? _file;

  File get file =>
      _file ?? File('${BlobStore.defaultRootPath}/app_settings.json');

  /// Null when nothing has been saved, or when the file is unreadable.
  ///
  /// A corrupt preferences file must never stop the window from opening, so a
  /// failure here is answered with "no preference" rather than an exception.
  Future<String?> readThemeMode() async {
    final settings = await _read();
    final value = settings[_themeModeKey];
    return value is String ? value : null;
  }

  Future<void> writeThemeMode({required String name}) async {
    final settings = await _read();
    settings[_themeModeKey] = name;
    await _write(settings: settings);
  }

  Future<Map<String, Object?>> _read() async {
    try {
      if (!file.existsSync()) return <String, Object?>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return <String, Object?>{};
      return Map<String, Object?>.from(decoded);
    } on Object {
      return <String, Object?>{};
    }
  }

  /// A preference is not worth failing over: if the directory is read-only or
  /// the disk is full, the choice simply does not survive the session.
  Future<void> _write({required Map<String, Object?> settings}) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(settings));
    } on Object {
      return;
    }
  }
}
