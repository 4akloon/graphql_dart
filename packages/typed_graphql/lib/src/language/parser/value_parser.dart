import '../ast/object_field.dart';
import '../ast/operation_type.dart';
import '../ast/type_ref.dart';
import '../ast/value.dart';
import '../lexer/token.dart';
import 'token_cursor.dart';

/// Parses values, variables, type references, descriptions and operation
/// types: the productions every other part of the parser uses (spec
/// §2.9–§2.11).
final class ValueParser {
  /// Creates a parser reading from [cursor].
  ValueParser(this.cursor);

  /// The token stream.
  final TokenCursor cursor;

  /// `Value[?Const]`: with [isConst], a variable is an error.
  Value value({required bool isConst}) {
    final token = cursor.token;
    return switch ((token.kind, token.value)) {
      (.bracketLeft, _) => cursor.nested(() => _list(isConst: isConst)),
      (.braceLeft, _) => cursor.nested(() => _object(isConst: isConst)),
      (.int || .float || .name, _) => _scalar(token),
      (.string || .blockString, _) => string(),
      (.dollar, _) when isConst => _variableInConstant(),
      (.dollar, _) => variable(),
      _ => cursor.unexpected(),
    };
  }

  /// `Variable`: `$name`.
  Variable variable() {
    final start = cursor.token.start;
    cursor.expect(.dollar);
    final name = cursor.name();
    return Variable(name, start: start, end: cursor.lastEnd);
  }

  /// A string or block string.
  StringValue string() {
    final token = cursor.token;
    if (token case Token(kind: .string || .blockString, :final value?)) {
      cursor.advance();
      final isBlock = token.kind == .blockString;
      return StringValue(
        value,
        isBlock: isBlock,
        start: token.start,
        end: token.end,
      );
    }
    cursor.unexpected();
  }

  /// `Description`: a string before a definition, or null.
  StringValue? description() =>
      cursor.peek(.string) || cursor.peek(.blockString) ? string() : null;

  /// `Type`: a named, list or non-null type.
  TypeRef typeRef() {
    final start = cursor.token.start;
    final type = cursor.peek(.bracketLeft)
        ? cursor.nested(() => _listType(start))
        : namedType();
    return cursor.expectOptional(.bang)
        ? NonNullType(type, start: start, end: cursor.lastEnd)
        : type;
  }

  /// `NamedType`: a name.
  NamedType namedType() {
    final name = cursor.name();
    return NamedType(name, start: name.start, end: name.end);
  }

  /// `OperationType`: `query`, `mutation` or `subscription`.
  OperationType operationType() {
    final token = cursor.expect(.name);
    return switch (token.value) {
      'query' => .query,
      'mutation' => .mutation,
      'subscription' => .subscription,
      _ => cursor.unexpected(token),
    };
  }

  /// The number, boolean, null or enum value of [token], consumed.
  Value _scalar(Token token) {
    cursor.advance();
    final (start, end) = (token.start, token.end);
    return switch ((token.kind, token.value)) {
      (.int, final lexeme?) => IntValue(lexeme, start: start, end: end),
      (.float, final lexeme?) => FloatValue(lexeme, start: start, end: end),
      (.name, 'true') => BooleanValue(true, start: start, end: end),
      (.name, 'false') => BooleanValue(false, start: start, end: end),
      (.name, 'null') => NullValue(start: start, end: end),
      (.name, final name?) => EnumValue(name, start: start, end: end),
      _ => throw StateError('$token is not a scalar value token.'),
    };
  }

  /// `$name` where a constant is required: graphql-js names the variable
  /// in the message and points at the `$`.
  Never _variableInConstant() {
    final dollar = cursor.token;
    cursor.advance();
    if (cursor.token case Token(kind: .name, :final value?)) {
      cursor.fail(
        .variableInConstant,
        'Unexpected variable "\$$value" in constant value.',
        at: dollar,
      );
    }
    cursor.unexpected(dollar);
  }

  ListValue _list({required bool isConst}) {
    final start = cursor.token.start;
    final values = cursor.any(
      .bracketLeft,
      () => value(isConst: isConst),
      .bracketRight,
    );
    return ListValue(values, start: start, end: cursor.lastEnd);
  }

  ObjectValue _object({required bool isConst}) {
    final start = cursor.token.start;
    final fields = cursor.any(
      .braceLeft,
      () => _objectField(isConst: isConst),
      .braceRight,
    );
    return ObjectValue(fields, start: start, end: cursor.lastEnd);
  }

  ObjectField _objectField({required bool isConst}) {
    final start = cursor.token.start;
    final name = cursor.name();
    cursor.expect(.colon);
    final value = this.value(isConst: isConst);
    return ObjectField(name, value, start: start, end: cursor.lastEnd);
  }

  ListType _listType(int start) {
    cursor.expect(.bracketLeft);
    final type = typeRef();
    cursor.expect(.bracketRight);
    return ListType(type, start: start, end: cursor.lastEnd);
  }
}
