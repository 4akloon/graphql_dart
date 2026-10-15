import 'dart:io';

import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

/// A temporary project copied from the `operations` golden input, and the
/// way to run the command line in it.
final class CliProject {
  /// Copies the input into a new temporary directory.
  CliProject()
    : directory = Directory.systemTemp.createTempSync('codegen_cli') {
    final input = Directory('test/goldens/operations/input');
    for (final entity in input.listSync(recursive: true)) {
      if (entity is! File) continue;
      final target = File(
        '${directory.path}/${entity.path.substring(input.path.length + 1)}',
      );
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(entity.readAsStringSync());
    }
  }

  /// The project directory.
  final Directory directory;

  /// Everything written to the output stream by the last [run].
  final StringBuffer out = StringBuffer();

  /// Everything written to the error stream by the last [run].
  final StringBuffer err = StringBuffer();

  /// Runs [arguments] in the project; returns the exit code.
  int run(List<String> arguments) {
    out.clear();
    err.clear();
    return CodegenCommand(out, err, directory.path).run(arguments);
  }

  /// The file at [path], relative to the project.
  File file(String path) => File('${directory.path}/$path');

  /// Deletes the project.
  void delete() => directory.deleteSync(recursive: true);
}
