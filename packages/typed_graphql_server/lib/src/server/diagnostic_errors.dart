import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Turns the diagnostics of the core into the errors of a response.
@internal
final class DiagnosticErrors {
  /// Creates the converter.
  const DiagnosticErrors();

  /// One error for each error diagnostic in [diagnostics], in order: the
  /// message, the place and the related places as `locations`, and the
  /// diagnostic's id as `extensions.code`.
  ///
  /// Warnings are dropped, unless there is no error: a rejection never has
  /// zero errors, so then every diagnostic is reported.
  List<GraphQLError> of(List<Diagnostic> diagnostics) {
    final errors = diagnostics.where((diagnostic) => diagnostic.isError);
    return [
      for (final diagnostic in errors.isEmpty ? diagnostics : errors)
        GraphQLError(
          diagnostic.message,
          locations: diagnostic.locations,
          extensions: JsonObject({'code': JsonString(diagnostic.code.id)}),
        ),
    ];
  }
}
