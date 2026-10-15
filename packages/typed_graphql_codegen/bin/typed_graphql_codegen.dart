import 'dart:io';

import 'package:typed_graphql_codegen/src/cli/codegen_command.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await CodegenCommand(
    stdout,
    stderr,
    Directory.current.path,
    environment: Platform.environment,
  ).run(arguments);
}
