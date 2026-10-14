import 'package:typed_graphql/typed_graphql.dart';

/// The tokens and diagnostics of lexing one text, for tests.
final class Lexed {
  /// Lexes [text] to the end.
  factory Lexed(String text, {bool keepComments = false}) {
    final sink = DiagnosticSink();
    final lexer = Lexer(Source(text), sink, keepComments: keepComments);
    final tokens = <Token>[];
    for (var token = lexer.advance(); token.kind != .eof;) {
      tokens.add(token);
      token = lexer.advance();
    }
    return Lexed._(tokens, sink.diagnostics);
  }

  Lexed._(this.tokens, this.diagnostics);

  /// The tokens before the end.
  final List<Token> tokens;

  /// What the lexer reported.
  final List<Diagnostic> diagnostics;

  /// Each token as `kind start:end value`.
  List<String> get described => [
    for (final token in tokens)
      '${token.kind.name} ${token.start}:${token.end}'
          '${token.value == null ? '' : ' ${token.value}'}',
  ];

  /// Each diagnostic as `line:column id message`.
  List<String> get errors => [
    for (final diagnostic in diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];
}
