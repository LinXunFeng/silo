import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_core/silo_core.dart';

/// Placeholder shell.
///
/// The engine in `silo_core` is complete and exercised through `silo_cli`; this
/// app is scaffolded so the workspace is whole, and the UI is built on top of
/// the same library the CLI already uses.
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
      home: const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final targets = <DownloadTarget>[LmStudioTarget()];

    return MacosScaffold(
      children: <Widget>[
        ContentArea(
          builder: (context, scrollController) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text('Silo'),
                const SizedBox(height: 8),
                const Text('Download once, link everywhere.'),
                const SizedBox(height: 24),
                Text('Store: ${BlobStore.defaultRootPath}'),
                for (final target in targets)
                  Text('Target: ${target.displayName} — ${target.root.path}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
