import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

/// Keeps the native window's appearance in step with the Flutter theme.
///
/// The window Silo draws into is an AppKit window with its own light or dark
/// appearance, and Flutter repainting its content does not change it. Without
/// this, turning off macOS dark mode leaves the title bar, the toolbar's blur
/// and the sidebar's vibrancy dark behind freshly-repainted light content —
/// and pinning the window to an appearance the system is not using would be
/// broken in exactly the same way, permanently.
class AppBrightnessSync extends StatefulWidget {
  const AppBrightnessSync({super.key, required this.child});

  final Widget child;

  @override
  State<AppBrightnessSync> createState() => _AppBrightnessSyncState();
}

class _AppBrightnessSyncState extends State<AppBrightnessSync> {
  /// What the window was last told, so a rebuild that changed nothing does not
  /// cost a platform channel round trip.
  Brightness? _appliedBrightness;

  /// Reading the brightness here is also what subscribes to it, so every
  /// later change — the system's, or the user's own choice — lands here.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyBrightness(brightness: MacosTheme.brightnessOf(context));
  }

  void _applyBrightness({required Brightness brightness}) {
    if (_appliedBrightness == brightness) return;
    _appliedBrightness = brightness;
    unawaited(
      WindowManipulator.overrideMacOSBrightness(
        dark: brightness == Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
