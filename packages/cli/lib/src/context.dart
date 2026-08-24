import 'dart:io';

import 'package:silo_core/silo_core.dart';

/// Shared wiring for every command: which store, which sources, which targets.
///
/// Sources and targets are assembled here and nowhere else, so adding either is
/// a one-line change in one place.
class SiloContext {
  SiloContext({
    required this.store,
    required this.sources,
    required this.targets,
    required this.options,
  });

  final BlobStore store;
  final List<ModelSource> sources;
  final List<DownloadTarget> targets;
  final DownloadOptions options;

  /// Builds the default configuration.
  ///
  /// The mirror is listed first because this whole project exists because the
  /// origin is unusably slow from China — but both are kept, and which one is
  /// actually used is decided by measurement at download time, not by order.
  factory SiloContext.build({
    String? storePath,
    List<String>? sourceIds,
    String? lmStudioPath,
    int connections = 8,
    int? rateLimit,
    String? hfToken,
    bool verifyChecksum = true,
  }) {
    final HttpClient client = ChunkedDownloader.createHttpClient();

    final all = <ModelSource>[
      HuggingFaceSource.mirror(client: client, token: hfToken),
      ModelScopeSource(client: client),
      HuggingFaceSource(client: client, token: hfToken),
    ];

    var selected = all;
    if (sourceIds != null && sourceIds.isNotEmpty) {
      selected = <ModelSource>[];
      for (final String id in sourceIds) {
        final ModelSource? match =
            all.where((s) => s.id == id).firstOrNull;
        if (match == null) {
          throw ArgumentError(
            'unknown source "$id"; available: ${all.map((s) => s.id).join(', ')}',
          );
        }
        selected.add(match);
      }
    }

    return SiloContext(
      store: BlobStore(Directory(storePath ?? BlobStore.defaultRootPath)),
      sources: selected,
      targets: <DownloadTarget>[
        LmStudioTarget(
          root: lmStudioPath == null ? null : Directory(lmStudioPath),
        ),
      ],
      options: DownloadOptions(
        connections: connections,
        bytesPerSecond: rateLimit,
        verifyChecksum: verifyChecksum,
      ),
    );
  }

  SiloLibrary buildLibrary() => SiloLibrary(
        store: store,
        sources: sources,
        targets: targets,
        options: options,
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
