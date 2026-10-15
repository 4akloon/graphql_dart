import 'package:typed_graphql/typed_graphql.dart';

/// Thrown by `ExecutableSchemaBuilder.build` when the declared schema has
/// problems. A schema is code, so this is a programmer error, not bad input.
///
/// {@category builder}
final class SchemaBuildError extends Error {
  /// Creates the error for [diagnostics].
  SchemaBuildError(List<Diagnostic> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics);

  /// Every problem found, the builder's checks first, then the core
  /// validator's.
  final List<Diagnostic> diagnostics;

  @override
  String toString() => [
    'SchemaBuildError:',
    for (final diagnostic in diagnostics)
      '${diagnostic.code.id}: ${diagnostic.message}',
  ].join('\n');
}
