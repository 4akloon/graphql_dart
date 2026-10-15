import 'dart:io';

import 'package:typed_graphql_codegen/src/cli/codegen_command.dart';

void main(List<String> arguments) {
  exitCode = CodegenCommand(
    stdout,
    stderr,
    Directory.current.path,
  ).run(arguments);
}
