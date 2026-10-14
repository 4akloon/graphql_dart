import '../../diagnostics/diagnostic.dart';
import '../ast/document.dart';
import 'graphql_syntax_exception.dart';

/// The result of parsing a document: [ParseSuccess] or [ParseFailure],
/// both with every [diagnostics] (R1.5).
///
/// {@category language}
sealed class ParseResult(List<Diagnostic> diagnostics) {
  /// Creates a result.
  this;

  /// Every diagnostic of the parse, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);

  /// The document; throws a [GraphQLSyntaxException] with [diagnostics]
  /// when the parse failed. For tests and scripts.
  Document requireDocument() => switch (this) {
    ParseSuccess(:final document) => document,
    ParseFailure() => throw GraphQLSyntaxException(diagnostics),
  };
}

/// A document without syntax errors; [diagnostics] hold warnings only.
///
/// {@category language}
final class ParseSuccess(
  /// The document.
  final Document document,
  super.diagnostics,
) extends ParseResult {
  /// Creates a success.
  this;
}

/// A document with syntax errors.
///
/// {@category language}
final class ParseFailure(
  /// Every definition that parsed completely; a definition or selection
  /// with an error is left out, so the tree has no error nodes.
  final Document partial,
  super.diagnostics,
) extends ParseResult {
  /// Creates a failure.
  this;
}
