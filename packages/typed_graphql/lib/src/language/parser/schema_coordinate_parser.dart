import '../ast/name.dart';
import '../ast/schema_coordinate.dart';
import 'token_cursor.dart';

/// Parses the schema coordinate grammar (September2025 §2 "Schema
/// Coordinates"), as graphql-js's `parseSchemaCoordinate` does.
final class SchemaCoordinateParser {
  /// Creates a parser reading from [cursor], which must read a
  /// `SchemaCoordinateLexer`.
  SchemaCoordinateParser(this.cursor);

  /// The token stream.
  final TokenCursor cursor;

  /// `SchemaCoordinate`: `Name`, `Name.Name`, `Name.Name(Name:)`, `@Name`
  /// or `@Name(Name:)`.
  SchemaCoordinate coordinate() {
    final start = cursor.token.start;
    final isDirective = cursor.expectOptional(.at);
    final name = cursor.name();
    final memberName = !isDirective && cursor.expectOptional(.dot)
        ? cursor.name()
        : null;
    final hasArgument =
        (isDirective || memberName != null) && cursor.peek(.parenLeft);
    final argumentName = hasArgument ? _argumentName() : null;
    final end = cursor.lastEnd;
    return switch ((isDirective, memberName, argumentName)) {
      (true, _, final argument?) => DirectiveArgumentCoordinate(
        name,
        argument,
        start: start,
        end: end,
      ),
      (true, _, null) => DirectiveCoordinate(name, start: start, end: end),
      (false, final member?, final argument?) => ArgumentCoordinate(
        name,
        member,
        argument,
        start: start,
        end: end,
      ),
      (false, final member?, null) => MemberCoordinate(
        name,
        member,
        start: start,
        end: end,
      ),
      (false, null, _) => TypeCoordinate(name, start: start, end: end),
    };
  }

  /// `(Name:)`.
  Name _argumentName() {
    cursor.expect(.parenLeft);
    final name = cursor.name();
    cursor.expect(.colon);
    cursor.expect(.parenRight);
    return name;
  }
}
