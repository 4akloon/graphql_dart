import '../../diagnostics/diagnostic.dart';

/// Thrown by `requireDocument` when a document has syntax errors; it
/// carries every diagnostic of the parse.
///
/// {@category language}
final class GraphQLSyntaxException implements Exception {
  /// Creates an exception with [diagnostics].
  GraphQLSyntaxException(List<Diagnostic> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics);

  /// The diagnostics of the parse, in report order.
  final List<Diagnostic> diagnostics;

  @override
  String toString() =>
      'GraphQLSyntaxException:\n${diagnostics.map((d) => '  $d').join('\n')}';
}
