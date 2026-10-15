import 'package:typed_graphql/typed_graphql.dart';

/// The outcome of [SchemaLoader.load]: a valid schema or the problems that
/// stop one.
///
/// {@category codegen}
sealed class const SchemaLoadResult() {
  /// Creates a result.
  this;
}

/// A schema that was read, built and validated.
///
/// {@category codegen}
final class SchemaLoaded(
  /// The schema.
  final ValidSchema schema,
) extends SchemaLoadResult {
  /// Creates a result holding [schema].
  this;
}

/// A schema file with problems.
///
/// {@category codegen}
final class SchemaNotLoaded(
  List<Diagnostic> diagnostics,
) extends SchemaLoadResult {
  /// Creates a result with [diagnostics].
  this;

  /// The problems, in report order; they point into the file.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
