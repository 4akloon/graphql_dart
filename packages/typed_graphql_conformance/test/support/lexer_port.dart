import 'package:typed_graphql/typed_graphql.dart';

import 'error_json.dart';

/// graphql-js's lexer test helpers over [Lexer]: tokens as graphql-js
/// `Token` fields and lexer diagnostics as `GraphQLError` JSON.
final class LexerPort {
  /// Creates the helpers; they keep no state.
  const LexerPort();

  /// The first token of [text]: `lexOne`.
  Map<String, Object?> lexOne(String text) => _tokens(text, 1).last;

  /// The second token of [text]: `lexSecond`.
  Map<String, Object?> lexSecond(String text) => _tokens(text, 2).last;

  /// The kind of the first token of [text].
  TokenKind firstKind(String text) =>
      Lexer(Source(text), DiagnosticSink()).advance().kind;

  /// Every token of [text] up to the end, comments included, as graphql-js
  /// kinds (`<EOF>` last).
  List<String> kindsWithComments(String text) =>
      kinds(text, keepComments: true);

  /// Like [kindsWithComments], with comments kept only when [keepComments].
  List<String> kinds(String text, {bool keepComments = false}) {
    final lexer = Lexer(
      Source(text),
      DiagnosticSink(),
      keepComments: keepComments,
    );
    final kinds = <String>[];
    for (var token = lexer.advance(); ; token = lexer.advance()) {
      kinds.add(kindOf(token.kind));
      if (token.kind == TokenKind.eof) {
        return kinds;
      }
    }
  }

  /// The first token of [text] from a [SchemaCoordinateLexer].
  Map<String, Object?> coordinateLexOne(String text) {
    final source = Source(text);
    final lexer = SchemaCoordinateLexer(source, DiagnosticSink());
    return _json(source, lexer.advance());
  }

  /// The first diagnostic of reading [count] tokens of [text] with a
  /// [SchemaCoordinateLexer], which graphql-js throws.
  Map<String, Object?> coordinateSyntaxError(String text, {int count = 2}) {
    final sink = DiagnosticSink();
    final lexer = SchemaCoordinateLexer(Source(text), sink);
    for (var i = 0; i < count; i++) {
      lexer.advance();
    }
    return const ErrorJson().of(sink.diagnostics.first);
  }

  /// The first comment token of [text]: graphql-js reads it as
  /// `lexOne(text).prev`.
  Map<String, Object?> firstComment(String text) {
    final source = Source(text);
    final lexer = Lexer(source, DiagnosticSink(), keepComments: true);
    return _json(source, lexer.advance());
  }

  /// The first diagnostic of lexing two tokens of [text]:
  /// `expectSyntaxError`, which throws at the first error.
  Map<String, Object?> syntaxError(String text) {
    final sink = DiagnosticSink();
    final lexer = Lexer(Source(text), sink);
    lexer
      ..advance()
      ..advance();
    return const ErrorJson().of(sink.diagnostics.first);
  }

  /// [kind] as graphql-js's `TokenKind` value, such as `Name` or `{`.
  String kindOf(TokenKind kind) => kind.isPunctuator
      ? kind.description.replaceAll('"', '')
      : kind.description;

  List<Map<String, Object?>> _tokens(String text, int count) {
    final source = Source(text);
    final lexer = Lexer(source, DiagnosticSink());
    return [for (var i = 0; i < count; i++) _json(source, lexer.advance())];
  }

  Map<String, Object?> _json(Source source, Token token) {
    final location = source.locationOf(token.start);
    return {
      'kind': kindOf(token.kind),
      'start': token.start,
      'end': token.end,
      'line': location.line,
      'column': location.column,
      'value': token.value,
    };
  }
}
