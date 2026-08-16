import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:silo_core/silo_core.dart';

/// Placeholder shell.
///
/// The engine in `silo_core` is complete and driven from `silo_cli`; this app
/// is scaffolded so the workspace is whole. It does one real thing so that
/// running it proves something: it reads the actual store and the actual
/// LM Studio directory. Under the App Sandbox those paths silently resolve
/// into the app's container instead, so this screen is also the check that the
/// sandbox stays off.
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
      home: const LibraryScreen(),
    );
  }
}

/// What the app could see on disk at startup.
class _Snapshot {
  const _Snapshot({
    required this.storePath,
    required this.storeBytes,
    required this.blobCount,
    required this.entries,
    required this.targetPath,
    required this.targetPresent,
    required this.installed,
  });

  final String storePath;
  final int storeBytes;
  final int blobCount;
  final List<CatalogEntry> entries;
  final String targetPath;
  final bool targetPresent;
  final List<InstalledModel> installed;
}

Future<_Snapshot> _load() async {
  final store = BlobStore.defaultLocation();
  final target = LmStudioTarget();
  final library = SiloLibrary(
    store: store,
    sources: const <ModelSource>[],
    targets: <DownloadTarget>[target],
  );

  final catalog = await library.readCatalog();
  final bool present = await target.isPresent();

  return _Snapshot(
    storePath: store.root.path,
    storeBytes: await store.totalSize(),
    blobCount: (await store.listBlobs()).length,
    entries: catalog.entries,
    targetPath: target.root.path,
    targetPresent: present,
    installed: present ? await target.scanInstalled() : <InstalledModel>[],
  );
}

String _bytes(int value) {
  if (value < 1024) return '$value B';
  const units = <String>['KiB', 'MiB', 'GiB', 'TiB'];
  var size = value / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 2)} ${units[unit]}';
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<_Snapshot> _future = _load();

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Silo'),
        actions: <ToolbarItem>[
          ToolBarIconButton(
            label: 'Refresh',
            icon: const MacosIcon(CupertinoIcons.refresh),
            onPressed: _refresh,
            showLabel: false,
          ),
        ],
      ),
      children: <Widget>[
        ContentArea(
          builder: (context, scrollController) {
            return FutureBuilder<_Snapshot>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: ProgressCircle());
                }
                return _Body(
                  snapshot: snapshot.data!,
                  scrollController: scrollController,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.snapshot, required this.scrollController});

  final _Snapshot snapshot;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Download once, link everywhere.',
              style: theme.typography.title3),
          const SizedBox(height: 20),
          _Section(
            title: 'Store',
            subtitle: snapshot.storePath,
            body: Text(
              '${snapshot.entries.length} model(s), '
              '${snapshot.blobCount} blob(s), '
              '${_bytes(snapshot.storeBytes)} on disk',
              style: theme.typography.body,
            ),
          ),
          for (final entry in snapshot.entries)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                '${entry.ref.id}  ·  ${entry.variant}  ·  '
                '${_bytes(entry.totalSize)}  ·  ${entry.sourceId}',
                style: theme.typography.caption1,
              ),
            ),
          const SizedBox(height: 20),
          _Section(
            title: 'LM Studio',
            subtitle: snapshot.targetPath,
            body: Text(
              snapshot.targetPresent
                  ? '${snapshot.installed.length} model(s) installed'
                  : 'not installed',
              style: theme.typography.body,
            ),
          ),
          for (final model in snapshot.installed)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                '${model.ref.id}  ·  ${_bytes(model.totalSize)}  ·  '
                '${model.files.length} file(s)',
                style: theme.typography.caption1,
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String title;
  final String subtitle;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.typography.headline),
        const SizedBox(height: 2),
        Text(subtitle, style: theme.typography.caption2),
        const SizedBox(height: 6),
        body,
      ],
    );
  }
}
