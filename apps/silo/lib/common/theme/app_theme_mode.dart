/// Whether the window follows macOS, or is pinned to one appearance.
///
/// Its own enum rather than Flutter's [ThemeMode] because these names are
/// written to disk: a rename in the framework would otherwise silently reset
/// everyone's saved preference.
enum AppThemeMode {
  system,
  light,
  dark;

  /// Anything unrecognised — an older file, a hand-edited one — falls back to
  /// following the system, which is the only choice that is never wrong.
  static AppThemeMode parse({required String? name}) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return AppThemeMode.system;
  }
}
