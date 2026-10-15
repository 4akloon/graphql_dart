import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../generator/generated_file.dart';

/// Writes generated files under the project directory, or reports which of
/// them are out of date.
///
/// {@category codegen}
final class const OutputWriter(
  /// The directory of the configuration file; generated paths are relative
  /// to it.
  final String directory,
) {
  /// Creates a writer for the project in [directory].
  this;

  /// Writes every file of [files] whose content differs; never deletes.
  /// Returns the paths written.
  List<String> write(List<GeneratedFile> files) {
    final written = <String>[];
    for (final generated in files) {
      if (_isCurrent(generated)) continue;
      final file = File(p.join(directory, generated.path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(generated.text);
      written.add(generated.path);
    }
    return written;
  }

  /// A `GQL509` per file of [files] that is missing or differs; writes
  /// nothing.
  List<Diagnostic> outdated(List<GeneratedFile> files) => [
    for (final generated in files)
      if (!_isCurrent(generated))
        Diagnostic(
          .outputOutdated,
          .error,
          "The generated file '${generated.path}' is out of date; run "
          '`dart run typed_graphql_codegen generate`.',
        ),
  ];

  bool _isCurrent(GeneratedFile generated) {
    final file = File(p.join(directory, generated.path));
    return file.existsSync() && file.readAsStringSync() == generated.text;
  }
}
