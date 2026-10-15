import '../../diagnostics/suggestions.dart';
import '../../language/ast/value.dart';
import '../model/schema_type.dart';
import 'bounded_value_printer.dart';

/// Whether a constant literal is a value of a scalar or enum type, with
/// the messages of graphql-js's `coerceInputLiteral` of the built-in
/// scalars and of `GraphQLEnumType` (spec §3.5, §3.9).
///
/// A custom scalar accepts any literal, as graphql-js's default
/// `parseLiteral` does: only its codec, at execution, knows its values.
final class const LeafValueChecker() {
  /// Creates the checker; it keeps no state.
  this;

  // Bounded: a value nested deeper than the printer can recurse is not
  // printed whole (M3 deviation 14).
  static const BoundedValuePrinter _printer = BoundedValuePrinter();
  static const int _minInt = -2147483648;
  static const int _maxInt = 2147483647;
  static const int _longestInt = 11;
  static final RegExp _integer = RegExp(r'^-?(0|[1-9][0-9]*)$');

  /// The message of why [value] is not a value of [type]; null when it is.
  /// With [includesSuggestions], a wrong enum value gets graphql-js's
  /// "Did you mean the enum value" text.
  String? errorOf(
    Value value,
    SchemaType type, {
    bool includesSuggestions = false,
  }) => switch (type) {
    EnumType() => _enumError(value, type, includesSuggestions),
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
    // A node built in code may hold any text, which stays an error. The
    // text is checked before it is parsed: parsing digits takes quadratic
    // time, and neither "0x10" nor "+5" is an integer literal.
    final text = value is IntValue ? value.value : null;
    if (text == null || !_integer.hasMatch(text)) {
      return 'Int cannot represent non-integer value: ${_printer.print(value)}';
    }
    // No literal of more than eleven characters (ten digits and a sign) is
    // in range, and the rule needs no number to say so.
    final number = text.length > _longestInt ? null : int.parse(text);
    if (number == null || number < _minInt || number > _maxInt) {
      return 'Int cannot represent non 32-bit signed integer value: $text';
    }
    return null;
  }

  String? _enumError(Value value, EnumType type, bool includesSuggestions) {
    if (value is EnumValue && type.valueNamed(value.value) != null) {
      return null;
    }
    final printed = _printer.print(value);
    final message = value is EnumValue
        ? 'Value "$printed" does not exist in "${type.name}" enum.'
        : 'Enum "${type.name}" cannot represent non-enum value: $printed.';
    if (!includesSuggestions) {
      return message;
    }
    const suggestions = Suggestions();
    final names = [for (final known in type.values) known.name];
    return '$message'
        '${suggestions.didYouMean(suggestions.listFor(printed, names), subject: 'the enum value')}';
  }
}
