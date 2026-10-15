import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../generator/generated_file.dart';

/// Writes generated files under the project directory, or reports which of
/// them are out of date.
///
/// It looks only at the files the generator emits: a generated file whose
/// document was removed is neither deleted nor reported.
///
/// {@category codegen}
final class const OutputWriter(
  /// The directory of the configuration file; generated paths are relative
  /// to it.
  final String directory,
) {
  /// Creates a writer for the project in [directory].
  this;

  /// Writes every file of [files] whose content differs, through a temporary
  /// file in the same folder and a rename so that an interrupted run never
  /// leaves a truncated file; never deletes. Returns the paths written and a
  /// `GQL510` per file it could not write (the others are still written).
  ({List<String> written, List<Diagnostic> problems}) write(
    List<GeneratedFile> files,
  ) {
    final written = <String>[];
    final problems = <Diagnostic>[];
    for (final generated in files) {
      if (_state(generated) == _State.current) continue;
      try {
        _replace(generated);
        written.add(generated.path);
      } on FileSystemException catch (error) {
        problems.add(
          _problem(
            'write',
            generated.path,
            error.osError?.message ?? error.message,
          ),
        );
      }
    }
    return (written: written, problems: problems);
  }

  /// A `GQL509` per file of [files] that is missing or differs and a `GQL510`
  /// per file that exists but cannot be read; writes nothing.
  List<Diagnostic> outdated(List<GeneratedFile> files) {
    final found = <Diagnostic>[];
    for (final generated in files) {
      switch (_state(generated)) {
        case _State.current:
          break;
        case _State.outdated:
          found.add(
            Diagnostic(
              .outputOutdated,
              .error,
              "The generated file '${generated.path}' is out of date; run "
              '`dart run typed_graphql_codegen generate`.',
            ),
          );
        case _State.unreadable:
          found.add(
            _problem('read', generated.path, 'not a readable UTF-8 file'),
          );
      }
    }
    return found;
  }

  void _replace(GeneratedFile generated) {
    final file = File(p.join(directory, generated.path));
    file.parent.createSync(recursive: true);
    // A folder of its own: a fixed name next to the target could overwrite
    // a file of the user's.
    final folder = file.parent.createTempSync('.typed_graphql_');
    try {
      final temporary = File(p.join(folder.path, 'output'));
      temporary.writeAsStringSync(generated.text);
      temporary.renameSync(file.path);
    } finally {
      folder.deleteSync(recursive: true);
    }
  }

  _State _state(GeneratedFile generated) {
    final file = File(p.join(directory, generated.path));
    try {
      if (FileSystemEntity.isDirectorySync(file.path)) return _State.unreadable;
      if (!file.existsSync()) return _State.outdated;
      return file.readAsStringSync() == generated.text
          ? _State.current
          : _State.outdated;
    } on FileSystemException {
      return _State.unreadable;
    } on FormatException {
      return _State.unreadable;
    }
  }

  Diagnostic _problem(String verb, String path, String reason) => Diagnostic(
    .inputUnreadable,
    .error,
    "Cannot $verb '$path': $reason.",
  );
}

enum _State { current, outdated, unreadable }
