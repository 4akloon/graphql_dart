import 'dart:convert';

import 'json_value.dart';

/// graphql-js's `inspect` for a [JsonValue]: how a value is printed inside
/// a scalar's error message.
///
/// Strings are JSON-quoted, an object prints as `{ a: 1 }`, a list as
/// `[1, 2]` with at most ten items and then `... N more items`, and a list
/// or object nested more than two levels deep prints as `[Array]` or
/// `[Object]`, so the size of a message does not grow with a hostile value.
///
/// {@category protocol}
final class const JsonInspector() {
  /// Creates the inspector; it keeps no state.
  this;

  static const int _maxItems = 10;
  static const int _maxDepth = 2;

  /// [value] as graphql-js's `inspect` prints it.
  String inspect(JsonValue value) => _format(value, 0);

  String _format(JsonValue value, int ancestors) => switch (value) {
    JsonNull() => 'null',
    JsonBool(:final value) => '$value',
    JsonNumber(:final value) => _number(value),
    JsonString(:final value) => jsonEncode(value),
    JsonArray(:final items) => _list(items, ancestors + 1),
    JsonObject(:final fields) => _object(fields, ancestors + 1),
  };

  // JavaScript prints 1.0 as 1 and -0 as 0.
  String _number(num number) {
    final isWhole = number.isFinite && number == number.truncateToDouble();
    return isWhole && number.abs() < 1e21 ? '${number.toInt()}' : '$number';
  }

  String _list(List<JsonValue> items, int depth) {
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

  String _object(Map<String, JsonValue> fields, int depth) {
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
