import 'dart:io';

import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main(List<String> arguments) {
  exitCode = CodegenCommand(
    stdout,
    stderr,
    Directory.current.path,
  ).run(arguments);
}
