import 'package:typed_graphql/typed_graphql.dart';

/// graphql-js's `inspect`: how a value is printed inside an error message.
///
/// It reads a [JsonValue] or a plain Dart value (null, bool, num, String,
/// List, Map; anything else prints with `toString`). Strings are JSON
/// quoted, objects print as `{ a: 1 }`, lists as `[1, 2]` with at most ten
/// items and then `... N more items`, and a list or object nested more than
/// two levels deep prints as `[Array]` or `[Object]`, so the cost of a
/// message does not grow with the depth of a hostile value.
final class ValueInspector {
  /// Creates the inspector; it keeps no state.
  const ValueInspector();

  static const int _maxItems = 10;
  static const int _maxDepth = 2;

  /// [value] as graphql-js's `inspect` prints it.
  String inspect(Object? value) => _format(value, 0);

  String _format(Object? raw, int ancestors) {
    return switch (_plain(raw)) {
      null => 'null',
      final String text => _quote(text),
      final num number => _number(number),
      final List<Object?> items => _list(items, ancestors + 1),
      final Map<String, Object?> fields => _object(fields, ancestors + 1),
      final Map<Object?, Object?> fields => _object({
        for (final entry in fields.entries) '${entry.key}': entry.value,
      }, ancestors + 1),
      final Object other => '$other',
    };
  }

  // Unwraps a JSON value one level: its children stay JSON values, which
  // [_format] unwraps when it reaches them.
  Object? _plain(Object? raw) => switch (raw) {
    JsonNull() => null,
    JsonBool(:final value) => value,
    JsonNumber(:final value) => value,
    JsonString(:final value) => value,
    JsonArray(:final items) => items,
    JsonObject(:final fields) => fields,
    _ => raw,
  };

  // `JSON.stringify` of a string. The server may not import `dart:convert`
  // (spec 17.4), so the escapes are written here.
  String _quote(String text) {
    final quoted = StringBuffer('"');
    for (final unit in text.codeUnits) {
      quoted.write(switch (unit) {
        0x22 => r'\"',
        0x5C => r'\\',
        0x0A => r'\n',
        0x0D => r'\r',
        0x09 => r'\t',
        0x08 => r'\b',
        0x0C => r'\f',
        < 0x20 => '\\u${unit.toRadixString(16).padLeft(4, '0')}',
        _ => String.fromCharCode(unit),
      });
    }
    return '$quoted"';
  }

  // JavaScript prints 1.0 as 1 and -0 as 0.
  String _number(num number) {
    final isWhole = number.isFinite && number == number.truncateToDouble();
    return isWhole && number.abs() < 1e21 ? '${number.toInt()}' : '$number';
  }

  String _list(List<Object?> items, int depth) {
    if (items.isEmpty) {
      return '[]';
    }
    if (depth > _maxDepth) {
      return '[Array]';
    }
    final shown = items.length < _maxItems ? items.length : _maxItems;
    final remaining = items.length - shown;
    final parts = [
      for (var i = 0; i < shown; i++) _format(items[i], depth),
      if (remaining == 1) '... 1 more item',
      if (remaining > 1) '... $remaining more items',
    ];
    return '[${parts.join(', ')}]';
  }

  String _object(Map<String, Object?> fields, int depth) {
    if (fields.isEmpty) {
      return '{}';
    }
    if (depth > _maxDepth) {
      return '[Object]';
    }
    final properties = [
      for (final MapEntry(:key, :value) in fields.entries)
        '$key: ${_format(value, depth)}',
    ];
    return '{ ${properties.join(', ')} }';
  }
}
