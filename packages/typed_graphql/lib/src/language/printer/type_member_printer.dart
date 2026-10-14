import '../ast/enum_value_definition.dart';
import '../ast/field_definition.dart';
import '../ast/input_value_definition.dart';
import '../ast/operation_type_definition.dart';
import '../ast/type_ref.dart';
import 'print_layout.dart';
import 'value_printer.dart';

/// Prints the members that type definitions and extensions share:
/// fields, input values, enum values, root operation types and the lists
/// they form.
final class TypeMemberPrinter {
  /// Creates a printer that prints values with [values].
  const TypeMemberPrinter(this.values);

  /// The value, argument and directive printer.
  final ValuePrinter values;

  static const PrintLayout _layout = PrintLayout();

  /// `implements A & B`; `''` for none.
  String interfaces(List<NamedType> interfaces) => _layout.wrap(
    'implements ',
    _layout.join(interfaces.map(values.typeRef), ' & '),
  );

  /// `= A | B`; `''` for none.
  String unionMembers(List<NamedType> types) =>
      _layout.wrap('= ', _layout.join(types.map(values.typeRef), ' | '));

  /// `{ field ... }` of an object or interface; `''` for none.
  String fields(List<FieldDefinition> fields) =>
      _layout.block(fields.map(field));

  /// `{ input ... }` of an input object; `''` for none.
  String inputFields(List<InputValueDefinition> fields) =>
      _layout.block(fields.map(inputValue));

  /// `{ VALUE ... }` of an enum; `''` for none.
  String enumValues(List<EnumValueDefinition> enumValues) =>
      _layout.block(enumValues.map(enumValue));

  /// `{ query: Query ... }` of a schema; `''` for none.
  String operationTypes(List<OperationTypeDefinition> types) =>
      _layout.block(types.map(operationType));

  /// `(input ...)` of a field or a directive; `''` for none.
  String argumentDefinitions(List<InputValueDefinition> arguments) =>
      _layout.argumentDefinitions(arguments.map(inputValue).toList());

  /// `query: Query`.
  String operationType(OperationTypeDefinition definition) =>
      '${definition.operation.name}: ${values.typeRef(definition.type)}';

  /// A field definition, after its description.
  String field(FieldDefinition field) {
    final description = values.description(field.description);
    final arguments = argumentDefinitions(field.arguments);
    final type = values.typeRef(field.type);
    final directives = values.directives(field.directives);
    return '$description${field.name.value}$arguments: $type'
        '${_layout.wrap(' ', directives)}';
  }

  /// An argument or input field definition, after its description.
  String inputValue(InputValueDefinition value) {
    final defaultValue = value.defaultValue;
    return values.description(value.description) +
        _layout.join([
          '${value.name.value}: ${values.typeRef(value.type)}',
          if (defaultValue != null) '= ${values.value(defaultValue)}',
          values.directives(value.directives),
        ], ' ');
  }

  /// An enum value definition, after its description.
  String enumValue(EnumValueDefinition value) =>
      values.description(value.description) +
      _layout.join([
        value.name.value,
        values.directives(value.directives),
      ], ' ');
}
