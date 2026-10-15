import 'package:typed_graphql/typed_graphql.dart';

import 'generated_file.dart';

/// What `ClientGenerator.generate` produced: the files and every diagnostic,
/// warnings included.
///
/// {@category codegen}
final class GenerationResult(
  List<GeneratedFile> files,
  List<Diagnostic> diagnostics,
) {
  /// Creates a result; a result with errors has no [files].
  this;

  /// The files to write, sorted by path; empty when there are errors.
  final List<GeneratedFile> files = List.unmodifiable(files);

  /// Every diagnostic, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);

  /// Whether a diagnostic is an error.
  bool get hasErrors => diagnostics.any((diagnostic) => diagnostic.isError);
}
