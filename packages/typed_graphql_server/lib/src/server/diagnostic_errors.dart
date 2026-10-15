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
  List<GraphQLError> of(List<Diagnostic> diagnostics) => [
    for (final diagnostic in diagnostics)
      if (diagnostic.isError)
        GraphQLError(
          diagnostic.message,
          locations: diagnostic.locations,
          extensions: JsonObject({'code': JsonString(diagnostic.code.id)}),
        ),
  ];
}
