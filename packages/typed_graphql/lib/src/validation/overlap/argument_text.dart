import 'dart:convert';

import '../../language/ast/argument.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/value.dart';

/// A field's arguments as one text that is equal for two fields exactly
/// when graphql-js's `sameArguments` holds: the arguments sorted by name,
/// object fields sorted by name, each value tagged with its kind.
///
/// The text is built with a stack, so a value nested 100000 deep cannot
/// overflow the call stack, and kept per field.
final class ArgumentText {
  /// Creates an empty cache.
  ArgumentText();

  final Map<Field, String> _texts = Map.identity();

  /// The text of [field]'s arguments.
  String of(Field field) => _texts[field] ??= _text(field.arguments);

  String _text(List<Argument> arguments) {
    final sorted = [...arguments]
      ..sort((a, b) => a.name.value.compareTo(b.name.value));
    final pending = <Object>[
      for (final argument in sorted.reversed) ...[
        ',',
        argument.value,
        '${argument.name.value}:',
      ],
    ];
    final buffer = StringBuffer();
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case final String text:
          buffer.write(text);
        case final Value value:
          buffer.write(_scalarText(value, pending));
      }
    }
    return buffer.toString();
  }

  /// The text of [value] when it is a scalar; a list or an object puts
  /// its parts on [pending] instead and gives its opening bracket.
  String _scalarText(Value value, List<Object> pending) {
    switch (value) {
      case Variable(:final name):
        return '\$${name.value}';
      case IntValue(:final value):
        return 'i$value';
      case FloatValue(:final value):
        return 'f$value';
      case StringValue(:final value):
        return jsonEncode(value);
      case BooleanValue(:final value):
        return '$value';
      case NullValue():
        return 'null';
      case EnumValue(:final value):
        return 'e$value';
      case ListValue(:final values):
        pending.add(']');
        for (final item in values.reversed) {
          pending.addAll([',', item]);
        }
        return '[';
      case ObjectValue(:final fields):
        final sorted = [...fields]
          ..sort((a, b) => a.name.value.compareTo(b.name.value));
        pending.add('}');
        for (final field in sorted.reversed) {
          pending.addAll([',', field.value, '${field.name.value}:']);
        }
        return '{';
    }
  }
}
