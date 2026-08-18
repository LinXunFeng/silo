import 'dart:io';

import 'package:args/command_runner.dart';

import 'src/commands.dart';

/// Builds the `silo` command line.
CommandRunner<int> buildRunner() {
  final runner = CommandRunner<int>(
    'silo',
    'A local model library. Download once, link everywhere.',
  );

  runner.argParser
    ..addOption('store',
        help: 'Where the blob store lives.', valueHelp: '~/.silo')
    ..addMultiOption('source',
        help: 'Restrict to these sources, in order.',
        valueHelp: 'hf-mirror,modelscope')
    ..addOption('connections',
        abbr: 'j',
        defaultsTo: '8',
        help: 'Parallel connections per file. Mirrors throttle above ~16.')
    ..addOption('limit',
        help: 'Aggregate rate limit, e.g. 5M or 800k.', valueHelp: 'RATE')
    ..addOption('lmstudio-path',
        help: "Override LM Studio's models directory.")
    ..addOption('hf-token',
        help: 'HuggingFace token for gated repositories. '
            'Defaults to \$HF_TOKEN.')
    ..addFlag('verify',
        defaultsTo: true,
        help: 'Verify SHA-256 after download. Turning this off risks a '
            'silently corrupt model that only fails at load time.');

  runner
    ..addCommand(AddCommand())
    ..addCommand(LinkCommand())
    ..addCommand(ListCommand())
    ..addCommand(SearchCommand())
    ..addCommand(InspectCommand())
    ..addCommand(SourcesCommand())
    ..addCommand(QueueCommand())
    ..addCommand(ScanCommand())
    ..addCommand(UnlinkCommand())
    ..addCommand(GcCommand())
    ..addCommand(RemoveCommand());

  return runner;
}

/// Entry point shared by `bin/silo.dart` and tests.
Future<int> run(List<String> arguments) async {
  try {
    return await buildRunner().run(arguments) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  } on FormatException catch (e) {
    stderr.writeln('silo: ${e.message}');
    return 64;
  } on ArgumentError catch (e) {
    stderr.writeln('silo: ${e.message}');
    return 64;
  }
}
