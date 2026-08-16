import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_app/l10n/app_localizations.dart';
import 'package:silo_app/page/library/page/library_page.dart';

void main() {
  runApp(const SiloApp());
}

class SiloApp extends StatelessWidget {
  const SiloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'Silo',
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LibraryPage(),
    );
  }
}
