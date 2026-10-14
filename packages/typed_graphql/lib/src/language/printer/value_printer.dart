import '../ast/argument.dart';
import '../ast/directive.dart';
import '../ast/object_field.dart';
import '../ast/type_ref.dart';
import '../ast/value.dart';
import '../lexer/block_string.dart';
import 'print_layout.dart';
import 'quoted_string.dart';

/// Prints values, type references, arguments and directives: the parts
/// every definition shares.
final class ValuePrinter {
  /// Creates the printer; it keeps no state.
  const ValuePrinter();

  static const PrintLayout _layout = PrintLayout();

  /// A value; a list or object value too long for one line is wrapped.
  String value(Value value) => switch (value) {
    Variable(:final name) => '\$${name.value}',
    IntValue(:final value) || FloatValue(:final value) => value,
    StringValue(:final value, isBlock: true) => const BlockString().print(
      value,
    ),
    StringValue(:final value) => const QuotedString().print(value),
    BooleanValue(:final value) => '$value',
    NullValue() => 'null',
    EnumValue(:final value) => value,
    ListValue(:final values) => _list(values.map(this.value).toList()),
    ObjectValue(:final fields) => _object(fields.map(objectField).toList()),
  };

  /// A type reference, such as `[String!]!`.
  String typeRef(TypeRef type) => switch (type) {
    NamedType(:final name) => name.value,
    ListType(:final type) => '[${typeRef(type)}]',
    NonNullType(:final type) => '${typeRef(type)}!',
  };

  /// `name: value` of an argument.
  String argument(Argument argument) =>
      '${argument.name.value}: ${value(argument.value)}';

  /// `name: value` of an input object field.
  String objectField(ObjectField field) =>
      '${field.name.value}: ${value(field.value)}';

  /// `@name(arguments)`.
  String directive(Directive directive) {
    final arguments = _layout.join(directive.arguments.map(argument), ', ');
    return '@${directive.name.value}${_layout.wrap('(', arguments, ')')}';
  }

  /// [directives] separated by spaces; `''` for none.
  String directives(List<Directive> directives) =>
      _layout.join(directives.map(directive), ' ');

  /// A description on its own line before a definition; `''` for none.
  String description(StringValue? description) =>
      description == null ? '' : '${value(description)}\n';

  String _list(List<String> values) {
    final line = '[${_layout.join(values, ', ')}]';
    return line.length > PrintLayout.maxLineLength
        ? '[\n${_layout.indent(_layout.join(values, '\n'))}\n]'
        : line;
  }

  String _object(List<String> fields) {
    final line = '{ ${_layout.join(fields, ', ')} }';
    return line.length > PrintLayout.maxLineLength
        ? _layout.block(fields)
        : line;
  }
}
