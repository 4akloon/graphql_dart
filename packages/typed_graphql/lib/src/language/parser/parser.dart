import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import '../ast/node.dart';
import '../ast/type_ref.dart';
import '../ast/value.dart';
import '../lexer/lexer.dart';
import 'parse_element_result.dart';
import 'parser_options.dart';
import 'syntax_abort.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses GraphQL documents and single elements; it never throws on bad
/// input (R1.5): the result carries every diagnostic.
///
/// The grammar lives in collaborators, one per part of the language; this
/// class wires them to a [TokenCursor] and assembles results.
final class Parser {
  /// Creates a parser with [options].
  const Parser({this.options = const ParserOptions()});

  /// The limits and the working-draft grammar this parser accepts.
  final ParserOptions options;

  /// Parses [source] as one value, such as `[1, $a]`; with [isConst], a
  /// variable is an error.
  ParseElementResult<Value> parseValue(Source source, {bool isConst = false}) =>
      _element(source, (cursor) => ValueParser(cursor).value(isConst: isConst));

  /// Parses [source] as one type reference, such as `[String!]`.
  ParseElementResult<TypeRef> parseTypeRef(Source source) =>
      _element(source, (cursor) => ValueParser(cursor).typeRef());

  TokenCursor _cursor(Source source, DiagnosticSink sink) => TokenCursor(
    Lexer(source, sink, maxTokens: options.maxTokens),
    sink,
    maxDepth: options.maxDepth,
  );

  /// Parses [source] with [parse], which must read it to the end.
  ParseElementResult<T> _element<T extends Node>(
    Source source,
    T Function(TokenCursor cursor) parse,
  ) {
    final sink = DiagnosticSink();
    final cursor = _cursor(source, sink);
    try {
      final element = parse(cursor);
      cursor.expect(.eof);
      if (!sink.hasErrors) {
        return ParseElementSuccess(element, sink.diagnostics);
      }
    } on SyntaxAbort {
      // The error is in the sink; an element has no partial result.
    }
    return ParseElementFailure(sink.diagnostics);
  }
}
