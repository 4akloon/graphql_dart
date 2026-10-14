import '../../diagnostics/source.dart';
import 'token.dart';
import 'token_kind.dart';

/// A stream of tokens the parser reads: `Lexer` for documents,
/// `SchemaCoordinateLexer` for schema coordinates (graphql-js's
/// `LexerInterface`).
///
/// {@category language}
abstract interface class TokenSource {
  /// The document being read.
  Source get source;

  /// Whether a token limit stopped the reading before the end.
  bool get isLimitReached;

  /// The next token; [TokenKind.eof] at the end, and again on every later
  /// call. Text that is no token is one [TokenKind.error] token, reported
  /// to the sink.
  Token advance();
}
