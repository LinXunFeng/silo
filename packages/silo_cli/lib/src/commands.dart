import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:silo_core/silo_core.dart';

import 'context.dart';
import 'format.dart';

/// Base for commands that need a configured library.
abstract class SiloCommand extends Command<int> {
  SiloContext get context {
    final global = globalResults!;
    return SiloContext.build(
      storePath: global['store'] as String?,
      sourceIds: (global['source'] as List<String>).isEmpty
          ? null
          : global['source'] as List<String>,
      lmStudioPath: global['lmstudio-path'] as String?,
      connections: int.parse(global['connections'] as String),
      rateLimit: _parseRate(global['limit'] as String?),
      hfToken: global['hf-token'] as String? ??
          Platform.environment['HF_TOKEN'],
      verifyChecksum: global['verify'] as bool,
    );
  }

  void log(String message) => stdout.writeln(message);
  void warn(String message) => stderr.writeln(message);
}

int? _parseRate(String? value) {
  if (value == null || value.isEmpty) return null;
  final match =
      RegExp(r'^(\d+(?:\.\d+)?)\s*([kmg]?)b?/?s?$', caseSensitive: false)
          .firstMatch(value.trim());
  if (match == null) {
    throw ArgumentError('cannot read rate limit "$value" (try 5M or 800k)');
  }
  final double number = double.parse(match.group(1)!);
  const multipliers = <String, int>{'': 1, 'k': 1 << 10, 'm': 1 << 20, 'g': 1 << 30};
  return (number * multipliers[match.group(2)!.toLowerCase()]!).round();
}

/// `silo add` — pull a model into the library.
class AddCommand extends SiloCommand {
  AddCommand() {
    argParser
      ..addOption('variant',
          abbr: 'v',
          help: 'Quantisation or variant name, e.g. Q4_K_M. '
              'Defaults to Q4_K_M when present.')
      ..addOption('revision', help: 'Branch or tag to pull from.')
      ..addMultiOption('to',
          help: 'Also link into these targets once downloaded, e.g. lmstudio.')
      ..addFlag('race',
          defaultsTo: true,
          help: 'Measure source throughput before choosing one.');
  }

  @override
  String get name => 'add';

  @override
  String get description => 'Download a model into the Silo store.';

  @override
  String get invocation => 'silo add <author/repo> [options]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      warn('expected exactly one model reference, e.g. '
          'silo add Qwen/Qwen2.5-0.5B-Instruct-GGUF');
      return 64;
    }

    final ModelRef ref = ModelRef.parse(rest.single);
    final library = context.buildLibrary();
    final status = StatusLine();

    try {
      log('Resolving ${ref.id} ...');
      final result = await library.add(
        ref,
        variantName: argResults!['variant'] as String?,
        revision: argResults!['revision'] as String?,
        probeSourceSpeed: argResults!['race'] as bool,
        onLog: (message) {
          status.clear();
          log(message);
        },
        onProgress: (p) {
          status.update(
            '${progressBar(p.fraction)} ${(p.fraction * 100).toStringAsFixed(1)}% '
            '${formatBytes(p.receivedBytes)}/${formatBytes(p.totalBytes)} '
            '${formatRate(p.file.bytesPerSecond)} '
            'eta ${formatDuration(p.file.eta)} '
            '[${p.fileIndex + 1}/${p.fileCount}] ${p.fileName}',
          );
        },
      );

      status.finish(
        'Added ${result.entry.ref.id} (${result.entry.variant}) '
        'from ${result.sourceId}',
      );
      log('  ${formatBytes(result.downloadedBytes)} transferred'
          '${result.resumedBytes > 0 ? ', ${formatBytes(result.resumedBytes)} resumed' : ''}'
          '${result.dedupedBytes > 0 ? ', ${formatBytes(result.dedupedBytes)} already in store' : ''}');
      for (final file in result.entry.files) {
        log('  ${file.name}  ${formatBytes(file.size)}');
      }

      final targets = argResults!['to'] as List<String>;
      if (targets.isNotEmpty) {
        await _linkAndReport(library, ref, targets, result.entry.variant, log);
      } else {
        log('');
        log('Link it into a tool with:');
        log('  silo link ${ref.id} --to lmstudio');
      }
      return 0;
    } on Object catch (error) {
      status.clear();
      warn('add failed: $error');
      return 1;
    } finally {
      library.close();
    }
  }
}

Future<void> _linkAndReport(
  SiloLibrary library,
  ModelRef ref,
  List<String> targetIds,
  String? variant,
  void Function(String) log,
) async {
  final results = await library.link(
    ref,
    targetIds: targetIds,
    variantName: variant,
  );
  for (final result in results) {
    log('');
    log('Linked into ${result.targetId} at ${result.root.path}');
    for (final link in result.links) {
      final String how = switch (link.method) {
        LinkMethod.hardLink => 'hardlink',
        LinkMethod.alreadyLinked => 'already linked',
        LinkMethod.copy => 'COPY',
      };
      log('  $how  ${link.path}');
    }
    if (result.bytesOnDisk == 0) {
      log('  ${formatBytes(result.apparentSize)} visible, '
          '0 B extra on disk');
    } else {
      log('  ${formatBytes(result.apparentSize)} visible, '
          '${formatBytes(result.bytesOnDisk)} copied '
          '(destination is on another volume)');
    }
  }
}

/// `silo link` — distribute a stored model into local tools.
class LinkCommand extends SiloCommand {
  LinkCommand() {
    argParser
      ..addMultiOption('to',
          help: 'Targets to link into, e.g. lmstudio.', defaultsTo: <String>['lmstudio'])
      ..addOption('variant', abbr: 'v', help: 'Which stored variant to link.');
  }

  @override
  String get name => 'link';

  @override
  String get description =>
      'Hard-link a stored model into one or more local tools.';

  @override
  String get invocation => 'silo link <author/repo> --to lmstudio';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      warn('expected exactly one model reference');
      return 64;
    }

    final library = context.buildLibrary();
    try {
      await _linkAndReport(
        library,
        ModelRef.parse(rest.single),
        argResults!['to'] as List<String>,
        argResults!['variant'] as String?,
        log,
      );
      return 0;
    } on Object catch (error) {
      warn('link failed: $error');
      return 1;
    } finally {
      library.close();
    }
  }
}

/// `silo ls` — what is in the library.
class ListCommand extends SiloCommand {
  ListCommand() {
    argParser.addFlag('blobs',
        negatable: false, help: 'List raw blobs instead of models.');
  }

  @override
  String get name => 'ls';

  @override
  String get description => 'List models held in the Silo store.';

  @override
  Future<int> run() async {
    final ctx = context;
    final library = ctx.buildLibrary();
    try {
      if (argResults!['blobs'] as bool) {
        final blobs = await ctx.store.listBlobs();
        for (final String sha256 in blobs) {
          final int size = await ctx.store.blobFile(sha256).length();
          log('${sha256.substring(0, 12)}  ${formatBytes(size).padLeft(10)}');
        }
        log('${blobs.length} blob(s), ${formatBytes(await ctx.store.totalSize())}');
        return 0;
      }

      final catalog = await library.readCatalog();
      if (catalog.entries.isEmpty) {
        log('Library is empty. Add something with:');
        log('  silo add Qwen/Qwen2.5-0.5B-Instruct-GGUF');
        return 0;
      }

      for (final entry in catalog.entries) {
        final links = catalog.linksFor(entry.key);
        final Set<String> tools =
            links.map((l) => l.targetId).toSet();
        log(entry.ref.id);
        log('  variant  ${entry.variant}');
        log('  size     ${formatBytes(entry.totalSize)} '
            'across ${entry.files.length} file(s)');
        log('  source   ${entry.sourceId}@${entry.revision}');
        log('  linked   ${tools.isEmpty ? '(nowhere)' : tools.join(', ')}');
        log('');
      }

      // Physical is what the disk actually gave up. Logical is what the same
      // files would have cost stored conventionally: every catalogued file,
      // plus a full copy for every hard link a tool sees.
      final int physical = await ctx.store.totalSize();
      final sizeByDigest = <String, int>{
        for (final entry in catalog.entries)
          for (final file in entry.files) file.sha256: file.size,
      };
      final int catalogued =
          catalog.entries.fold<int>(0, (a, e) => a + e.totalSize);
      final int linked = catalog.links
          .where((l) => l.hardLinked)
          .fold<int>(0, (a, l) => a + (sizeByDigest[l.sha256] ?? 0));

      log('${catalog.entries.length} model(s), '
          '${formatBytes(physical)} on disk');
      if (catalog.links.isNotEmpty) {
        final int hardLinked = catalog.links.where((l) => l.hardLinked).length;
        log('${catalog.links.length} link(s) into tools, '
            '$hardLinked by hard link');
      }
      final int saved = catalogued + linked - physical;
      if (saved > 0) {
        log('Deduplication saved ${formatBytes(saved)} '
            '(${formatBytes(catalogued + linked)} visible to tools)');
      }
      return 0;
    } finally {
      library.close();
    }
  }
}

/// `silo inspect` — what variants exist upstream.
class InspectCommand extends SiloCommand {
  InspectCommand() {
    argParser.addOption('revision', help: 'Branch or tag to inspect.');
  }

  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Show the variants a model repository offers, across all sources.';

  @override
  String get invocation => 'silo inspect <author/repo>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      warn('expected exactly one model reference');
      return 64;
    }

    final library = context.buildLibrary();
    try {
      final ModelRef ref = ModelRef.parse(rest.single);
      final result = await library.inspect(
        ref,
        revision: argResults!['revision'] as String?,
        onLog: warn,
      );

      log(ref.id);
      log('  available from: '
          '${result.sources.map((s) => s.source.id).join(', ')}');
      log('');
      for (final variant in result.variants) {
        final parts = variant.isSharded ? ' ${variant.parts.length} shards' : '';
        // Companions mean different things per format: a projector for GGUF,
        // the mandatory config/tokenizer set for safetensors.
        final companions = variant.companions.isEmpty
            ? ''
            : switch (variant.format) {
                ModelFormat.gguf => ' +${variant.companions.length} mmproj',
                _ => ' +${variant.companions.length} support files',
              };
        log('  ${variant.name.padRight(44)} '
            '${formatBytes(variant.totalSize).padLeft(10)}$parts$companions');
      }
      log('');
      log('Download one with:');
      log('  silo add ${ref.id} -v ${result.variants.isEmpty ? 'Q4_K_M' : result.variants.first.name}');
      return 0;
    } on Object catch (error) {
      warn('inspect failed: $error');
      return 1;
    } finally {
      library.close();
    }
  }
}

/// `silo sources` — which sources are configured, and how fast they are.
class SourcesCommand extends SiloCommand {
  SourcesCommand() {
    argParser.addOption('probe',
        help: 'Measure throughput using this model repository.');
  }

  @override
  String get name => 'sources';

  @override
  String get description => 'List configured sources, optionally racing them.';

  @override
  Future<int> run() async {
    final ctx = context;
    for (final source in ctx.sources) {
      log('${source.id.padRight(14)} ${source.displayName}');
    }

    final String? probe = argResults!['probe'] as String?;
    if (probe == null) {
      log('');
      log('Measure them with:  silo sources --probe Qwen/Qwen2.5-0.5B-Instruct-GGUF');
      return 0;
    }

    final library = ctx.buildLibrary();
    try {
      final ModelRef ref = ModelRef.parse(probe);
      log('');
      log('Racing sources on ${ref.id} ...');
      final resolved = await resolveSources(
        ctx.sources,
        ref,
        onError: (source, error) => warn('  ${source.id} unavailable: $error'),
      );
      if (resolved.isEmpty) {
        warn('no source has ${ref.id}');
        return 1;
      }

      final variants = groupVariants(resolved.first.listing.files, repoName: ref.repo);
      if (variants.isEmpty) {
        warn('${ref.id} has no weight files to probe with');
        return 1;
      }

      final speeds = await raceSources(resolved, variants.first.parts.first.path);
      for (final speed in speeds) {
        log('  ${speed.source.id.padRight(14)} '
            '${speed.ok ? formatRate(speed.bytesPerSecond) : 'unavailable (${speed.error})'}');
      }
      return 0;
    } finally {
      library.close();
    }
  }
}

/// `silo gc` — reclaim blobs nothing references.
class GcCommand extends SiloCommand {
  GcCommand() {
    argParser.addFlag('dry-run',
        negatable: false, help: 'Report what would be freed, delete nothing.');
  }

  @override
  String get name => 'gc';

  @override
  String get description => 'Delete blobs no model in the library references.';

  @override
  Future<int> run() async {
    final library = context.buildLibrary();
    try {
      final bool dryRun = argResults!['dry-run'] as bool;
      final result = await library.gc(dryRun: dryRun);
      if (result.blobs == 0) {
        log('Nothing to collect.');
        return 0;
      }
      log(dryRun
          ? 'Would free ${formatBytes(result.bytes)} across ${result.blobs} blob(s)'
          : 'Freed ${formatBytes(result.bytes)} across ${result.blobs} blob(s)');
      return 0;
    } finally {
      library.close();
    }
  }
}

/// `silo rm` — forget a model, leaving gc to reclaim the space.
class RemoveCommand extends SiloCommand {
  RemoveCommand() {
    argParser.addOption('variant', abbr: 'v', help: 'Only forget this variant.');
  }

  @override
  String get name => 'rm';

  @override
  String get description =>
      'Forget a model. Its blobs are freed by the next `silo gc`.';

  @override
  String get invocation => 'silo rm <author/repo>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      warn('expected exactly one model reference');
      return 64;
    }

    final library = context.buildLibrary();
    try {
      final ModelRef ref = ModelRef.parse(rest.single);
      final bool removed = await library.forget(
        ref,
        variantName: argResults!['variant'] as String?,
      );
      if (!removed) {
        warn('${ref.id} is not in the library');
        return 1;
      }
      log('Forgot ${ref.id}. Run `silo gc` to reclaim the space.');
      return 0;
    } finally {
      library.close();
    }
  }
}

/// `silo scan` — what tools already have, so nothing is downloaded twice.
class ScanCommand extends SiloCommand {
  @override
  String get name => 'scan';

  @override
  String get description =>
      'Report models already installed in local tools.';

  @override
  Future<int> run() async {
    final ctx = context;
    for (final target in ctx.targets) {
      final bool present = await target.isPresent();
      log('${target.displayName} (${target.root.path})'
          '${present ? '' : ' — not installed'}');
      if (!present) continue;

      if (target is LmStudioTarget) {
        final installed = await target.scanInstalled();
        if (installed.isEmpty) {
          log('  (no models)');
        }
        for (final model in installed) {
          log('  ${model.ref.id.padRight(52)} '
              '${formatBytes(model.totalSize).padLeft(10)} '
              '${model.files.length} file(s)');
        }
      }
      log('');
    }
    return 0;
  }
}
