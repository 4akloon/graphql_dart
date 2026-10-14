import '../../language/ast/value.dart';
import '../../language/printer/printer.dart';
import '../model/schema_type.dart';

/// Whether a constant literal is a value of a scalar or enum type, with
/// the messages of graphql-js's `coerceInputLiteral` of the built-in
/// scalars and of `GraphQLEnumType` (spec §3.5, §3.9).
///
/// A custom scalar accepts any literal, as graphql-js's default
/// `parseLiteral` does: only its codec, at execution, knows its values.
final class const LeafValueChecker() {
  /// Creates the checker; it keeps no state.
  this;

  static const Printer _printer = Printer();
  static final BigInt _minInt = BigInt.from(-2147483648);
  static final BigInt _maxInt = BigInt.from(2147483647);

  /// The message of why [value] is not a value of [type]; null when it is.
  String? errorOf(Value value, SchemaType type) => switch (type) {
    EnumType() => _enumError(value, type),
    ScalarType(name: 'Int') => _intError(value),
    ScalarType(name: 'Float') when value is! IntValue && value is! FloatValue =>
      'Float cannot represent non numeric value: ${_printer.print(value)}',
    ScalarType(name: 'String') when value is! StringValue =>
      'String cannot represent a non string value: ${_printer.print(value)}',
    ScalarType(name: 'Boolean') when value is! BooleanValue =>
      'Boolean cannot represent a non boolean value: ${_printer.print(value)}',
    ScalarType(name: 'ID') when value is! StringValue && value is! IntValue =>
      'ID cannot represent a non-string and non-integer value: '
          '${_printer.print(value)}',
    _ => null,
  };

  String? _intError(Value value) {
    // A node built in code may hold any text; tryParse keeps it an error.
    final text = value is IntValue ? value.value : null;
    final number = text == null ? null : BigInt.tryParse(text);
    if (number == null) {
      return 'Int cannot represent non-integer value: ${_printer.print(value)}';
    }
    if (number < _minInt || number > _maxInt) {
      return 'Int cannot represent non 32-bit signed integer value: $text';
    }
    return null;
  }

  String? _enumError(Value value, EnumType type) {
    if (value is! EnumValue) {
      return 'Enum "${type.name}" cannot represent non-enum value: '
          '${_printer.print(value)}.';
    }
    if (type.valueNamed(value.value) == null) {
      return 'Value "${value.value}" does not exist in "${type.name}" enum.';
    }
    return null;
  }
}
