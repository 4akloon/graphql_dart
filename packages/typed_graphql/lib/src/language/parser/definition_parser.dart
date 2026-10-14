import '../ast/definition.dart';
import '../lexer/token.dart';
import 'executable_parser.dart';
import 'token_cursor.dart';

/// Parses one definition of a document: it reads the keyword, after an
/// optional description, and hands over to the part of the grammar that
/// owns it (spec §2.2).
final class DefinitionParser {
  /// Creates a parser reading from [cursor].
  DefinitionParser(this.cursor, this.executable);

  /// The token stream.
  final TokenCursor cursor;

  /// Operations and fragments.
  final ExecutableParser executable;

  /// `Definition`, with graphql-js's messages for a misplaced description.
  Definition definition() {
    if (cursor.peek(.braceLeft)) {
      return executable.operation();
    }
    final hasDescription = cursor.peek(.string) || cursor.peek(.blockString);
    final keyword = hasDescription ? cursor.lookahead() : cursor.token;
    if (hasDescription && keyword.kind == .braceLeft) {
      cursor.fail(
        .misplacedDescription,
        'Unexpected description, descriptions are not supported on '
        'shorthand queries.',
      );
    }
    return switch (keyword) {
      Token(kind: .name, value: 'query' || 'mutation' || 'subscription') =>
        executable.operation(),
      Token(kind: .name, value: 'fragment') => executable.fragment(),
      Token(kind: .name) when hasDescription => cursor.fail(
        .misplacedDescription,
        'Unexpected description, only GraphQL definitions support '
        'descriptions.',
      ),
      _ => cursor.unexpected(keyword),
    };
  }
}
