import 'package:typed_graphql/typed_graphql.dart';

/// A diagnostic as graphql-js's `GraphQLError` JSON for a syntax error, so a
/// ported `expectSyntaxError(...)` expectation is copied unchanged.
final class ErrorJson {
  /// Creates the converter; it keeps no state.
  const ErrorJson();

  /// `{message: 'Syntax Error: ...', locations: [{line, column}]}`.
  Map<String, Object?> of(Diagnostic diagnostic) {
    final location = diagnostic.span?.location;
    return {
      'message': 'Syntax Error: ${diagnostic.message}',
      'locations': [
        if (location != null)
          {'line': location.line, 'column': location.column},
      ],
    };
  }
}
