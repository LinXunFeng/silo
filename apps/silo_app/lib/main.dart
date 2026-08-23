import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/common/theme/app_theme_logic.dart';
import 'package:silo_app/common/theme/app_theme_scope.dart';
import 'package:silo_app/common/widget/app_brightness_sync.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/page/library_page.dart';

/// Sets up the AppKit window before the first frame.
///
/// [MacosWindow] draws a transparent title bar and a vibrant sidebar over the
/// real window, and none of that exists until macos_ui has been allowed to
/// configure it. Skipping this leaves the window in its default state, which
/// is where the appearance and the content stop agreeing with each other.
Future<void> main() async {
  await const MacosWindowUtilsConfig().apply();
  Get.put(AppThemeLogic());
  runApp(const SiloApp());
}

class SiloApp extends StatelessWidget {
  const SiloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AppThemeLogic>(
      builder: (logic) => _buildApp(logic: logic),
    );
  }

  /// No `theme` or `darkTheme` here on purpose.
  ///
  /// macos_ui only injects the system accent colour and the window's active
  /// state into a theme it builds itself; supplying one takes that away from
  /// every native control in the window. [AppThemeScope] makes this app's
  /// adjustments one level down instead.
  Widget _buildApp({required AppThemeLogic logic}) {
    return MacosApp(
      title: 'Silo',
      themeMode: logic.resolvedThemeMode,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AppThemeScope(
        child: AppBrightnessSync(child: LibraryPage()),
      ),
    );
  }
}
