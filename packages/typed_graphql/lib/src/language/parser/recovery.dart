import '../lexer/token.dart';
import '../lexer/token_kind.dart';
import 'token_cursor.dart';
import 'type_system_parser.dart';

/// Where the parser resumes after a syntax error (R1.5): it skips tokens
/// to the next place where a definition or a selection can start, at the
/// bracket level where the failed one started.
final class Recovery {
  /// Creates the policy for [cursor].
  Recovery(this.cursor);

  /// The token stream.
  final TokenCursor cursor;

  static const Set<String> _definitionKeywords = {
    ...TypeSystemParser.keywords,
    'query',
    'mutation',
    'subscription',
    'fragment',
    'extend',
  };

  /// Skips the rest of a definition that started at [first] when the
  /// cursor's balance was [balance].
  void skipDefinition(Token first, int balance) =>
      _skip(first, balance, _startsDefinition);

  /// Skips the rest of a selection that started at [first] when the
  /// cursor's balance was [balance]; it stops before a name, `...` or the
  /// `}` that closes the selection set.
  void skipSelection(Token first, int balance) =>
      _skip(first, balance, _startsSelection);

  /// Consumes at least one token, so the parser always moves on, then
  /// every token up to a [isResumable] one at [balance] or below, or the
  /// end.
  void _skip(Token first, int balance, bool Function(Token) isResumable) {
    if (identical(cursor.token, first)) {
      cursor.advance();
    }
    while (!cursor.peek(.eof) &&
        !(cursor.balance <= balance && isResumable(cursor.token))) {
      cursor.advance();
    }
  }

  /// A `{` starts a definition only after a closed block or at the start;
  /// elsewhere it opens the body of the failed definition, which is
  /// skipped with it.
  bool _startsDefinition(Token token) => switch (token.kind) {
    .braceLeft => cursor.lastKind == null || cursor.lastKind == .braceRight,
    .string || .blockString => true,
    // After `@` a keyword is a directive's name, not a definition.
    .name =>
      cursor.lastKind != .at && _definitionKeywords.contains(token.value),
    _ => false,
  };

  static bool _startsSelection(Token token) =>
      token.kind == TokenKind.name ||
      token.kind == TokenKind.spread ||
      token.kind == TokenKind.braceRight;
}
