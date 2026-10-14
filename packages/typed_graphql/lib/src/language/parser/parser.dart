import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import '../ast/definition.dart';
import '../ast/document.dart';
import '../ast/node.dart';
import '../ast/schema_coordinate.dart';
import '../ast/type_ref.dart';
import '../ast/value.dart';
import '../lexer/lexer.dart';
import '../lexer/schema_coordinate_lexer.dart';
import 'definition_parser.dart';
import 'directive_extension_grammar.dart';
import 'directive_parser.dart';
import 'executable_parser.dart';
import 'extension_parser.dart';
import 'parse_element_result.dart';
import 'parse_result.dart';
import 'parser_options.dart';
import 'recovery.dart';
import 'schema_coordinate_parser.dart';
import 'selection_parser.dart';
import 'syntax_abort.dart';
import 'token_cursor.dart';
import 'type_member_parser.dart';
import 'type_system_parser.dart';
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

  /// Parses [source] as a document. A definition with a syntax error is
  /// reported and left out, and parsing resumes at the next definition.
  ParseResult parse(Source source) {
    final sink = DiagnosticSink();
    final cursor = _cursor(source, sink);
    final definitions = _definitions(cursor);
    final recovery = Recovery(cursor);
    final parsed = <Definition>[];
    do {
      final first = cursor.token;
      final balance = cursor.balance;
      try {
        parsed.add(definitions.definition());
      } on SyntaxAbort {
        recovery.skipDefinition(first, balance);
      }
    } while (!cursor.peek(.eof) && !cursor.isStopped);
    final document = Document(parsed, start: 0, end: source.body.length);
    return sink.hasErrors
        ? ParseFailure(document, sink.diagnostics)
        : ParseSuccess(document, sink.diagnostics);
  }

  /// Parses [source] as one value, such as `[1, $a]`; with [isConst], a
  /// variable is an error.
  ParseElementResult<Value> parseValue(Source source, {bool isConst = false}) =>
      _element(source, (cursor) => ValueParser(cursor).value(isConst: isConst));

  /// Parses [source] as one type reference, such as `[String!]`.
  ParseElementResult<TypeRef> parseTypeRef(Source source) =>
      _element(source, (cursor) => ValueParser(cursor).typeRef());

  /// Parses [source] as a schema coordinate, such as `Query.hero(id:)`,
  /// which holds no ignored tokens. [options] do not apply: a coordinate
  /// has no limits and no working-draft syntax.
  ParseElementResult<SchemaCoordinate> parseSchemaCoordinate(Source source) {
    final sink = DiagnosticSink();
    final cursor = TokenCursor(SchemaCoordinateLexer(source, sink), sink);
    return _complete(cursor, SchemaCoordinateParser(cursor).coordinate);
  }

  TokenCursor _cursor(Source source, DiagnosticSink sink) => TokenCursor(
    Lexer(source, sink, maxTokens: options.maxTokens),
    sink,
    maxDepth: options.maxDepth,
  );

  DefinitionParser _definitions(TokenCursor cursor) {
    final values = ValueParser(cursor);
    final directives = DirectiveParser(cursor, values);
    final selections = SelectionParser(
      cursor,
      values,
      directives,
      allowsEmpty: options.allowEmptySelectionSets,
    );
    final members = TypeMemberParser(cursor, values, directives);
    final allowsDirectiveExtensions = options.allowDirectiveExtensions;
    return DefinitionParser(
      cursor,
      ExecutableParser(cursor, values, directives, selections),
      TypeSystemParser(
        cursor,
        values,
        directives,
        members,
        allowsDirectiveExtensions: allowsDirectiveExtensions,
      ),
      ExtensionParser(cursor, directives, members),
      [
        DirectiveExtensionGrammar(
          cursor,
          directives,
          isEnabled: allowsDirectiveExtensions,
        ),
      ],
    );
  }

  /// Parses [source] with [parse], which must read it to the end.
  ParseElementResult<T> _element<T extends Node>(
    Source source,
    T Function(TokenCursor cursor) parse,
  ) {
    final sink = DiagnosticSink();
    final cursor = _cursor(source, sink);
    return _complete(cursor, () => parse(cursor));
  }

  /// The element [parse] reads from [cursor], which must then be at the
  /// end; a failure when the cursor's sink has an error.
  ParseElementResult<T> _complete<T extends Node>(
    TokenCursor cursor,
    T Function() parse,
  ) {
    final sink = cursor.sink;
    try {
      final element = parse();
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
