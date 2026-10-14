import '../ast/enum_value_definition.dart';
import '../ast/field_definition.dart';
import '../ast/input_value_definition.dart';
import '../ast/name.dart';
import '../ast/operation_type_definition.dart';
import '../ast/type_ref.dart';
import '../lexer/token.dart';
import 'directive_parser.dart';
import 'token_cursor.dart';
import 'value_parser.dart';

/// Parses what type-system definitions and extensions share: fields,
/// input values, enum values, interfaces, union members and root
/// operation types (spec §3).
final class TypeMemberParser {
  /// Creates a parser reading from [cursor].
  TypeMemberParser(this.cursor, this.values, this.directives);

  /// The token stream.
  final TokenCursor cursor;

  /// The value productions.
  final ValueParser values;

  /// The directive and argument productions.
  final DirectiveParser directives;

  /// `ImplementsInterfaces`: `implements A & B`, or none.
  List<NamedType> interfaces() => cursor.expectOptionalKeyword('implements')
      ? cursor.delimitedMany(.ampersand, values.namedType)
      : <NamedType>[];

  /// `UnionMemberTypes`: `= A | B`, or none.
  List<NamedType> unionMembers() => cursor.expectOptional(.equals)
      ? cursor.delimitedMany(.pipe, values.namedType)
      : <NamedType>[];

  /// `FieldsDefinition`: `{ field ... }`, or none.
  List<FieldDefinition> fields() =>
      cursor.optionalMany(.braceLeft, _field, .braceRight);

  /// `ArgumentsDefinition`: `(input ...)`, or none.
  List<InputValueDefinition> arguments() =>
      cursor.optionalMany(.parenLeft, _inputValue, .parenRight);

  /// `InputFieldsDefinition`: `{ input ... }`, or none.
  List<InputValueDefinition> inputFields() =>
      cursor.optionalMany(.braceLeft, _inputValue, .braceRight);

  /// `EnumValuesDefinition`: `{ VALUE ... }`, or none.
  List<EnumValueDefinition> enumValues() =>
      cursor.optionalMany(.braceLeft, _enumValue, .braceRight);

  /// `RootOperationTypeDefinition`: `query: Query`.
  OperationTypeDefinition operationType() {
    final start = cursor.token.start;
    final operation = values.operationType();
    cursor.expect(.colon);
    final type = values.namedType();
    return OperationTypeDefinition(
      operation,
      type,
      start: start,
      end: cursor.lastEnd,
    );
  }

  FieldDefinition _field() {
    final start = cursor.token.start;
    final description = values.description();
    final name = cursor.name();
    final arguments = this.arguments();
    cursor.expect(.colon);
    final type = values.typeRef();
    final directiveList = directives.directives(isConst: true);
    return FieldDefinition(
      name,
      type,
      description: description,
      arguments: arguments,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  InputValueDefinition _inputValue() {
    final start = cursor.token.start;
    final description = values.description();
    final name = cursor.name();
    cursor.expect(.colon);
    final type = values.typeRef();
    final defaultValue = cursor.expectOptional(.equals)
        ? values.value(isConst: true)
        : null;
    final directiveList = directives.directives(isConst: true);
    return InputValueDefinition(
      name,
      type,
      description: description,
      defaultValue: defaultValue,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  EnumValueDefinition _enumValue() {
    final start = cursor.token.start;
    final description = values.description();
    final name = _enumValueName();
    final directiveList = directives.directives(isConst: true);
    return EnumValueDefinition(
      name,
      description: description,
      directives: directiveList,
      start: start,
      end: cursor.lastEnd,
    );
  }

  Name _enumValueName() {
    final token = cursor.token;
    if (token case Token(kind: .name, value: 'true' || 'false' || 'null')) {
      cursor.fail(
        .reservedEnumValueName,
        '${token.description} is reserved and cannot be used for an enum '
        'value.',
      );
    }
    return cursor.name();
  }
}
