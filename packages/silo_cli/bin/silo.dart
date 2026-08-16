import 'dart:io';

import 'package:silo_cli/silo_cli.dart' as cli;

Future<void> main(List<String> arguments) async {
  exitCode = await cli.run(arguments);
}
