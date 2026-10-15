import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

/// graphql-js's `inspect` for the Dart values a coerced argument holds, as
/// the ported variable tests print them: strings JSON-quoted, `{ a: 1 }`,
/// `[1, 2]`, ten items at most, nesting cut at depth two. A [JsonValue] is
/// printed as the plain value it stands for and any other object with its
/// `toString`.
final class JsInspect {
  /// Creates the inspector; it keeps no state.
  const JsInspect();

  /// [value] as `inspect` prints it.
  String call(Object? value) => _format(value, 0);

  String _format(Object? value, int ancestors) => switch (value) {
    null || JsonNull() => 'null',
    final JsonValue json => _format(json.toJson(), ancestors),
    final String text => jsonEncode(text),
    final num number => _number(number),
    final List<Object?> items => _list(items, ancestors + 1),
    final Map<Object?, Object?> fields => _object(fields, ancestors + 1),
    _ => '$value',
  };

  String _number(num number) {
    final isWhole = number.isFinite && number == number.truncateToDouble();
    return isWhole && number.abs() < 1e21 ? '${number.toInt()}' : '$number';
  }

  String _list(List<Object?> items, int depth) {
    if (items.isEmpty) {
      return '[]';
    }
    if (depth > 2) {
      return '[Array]';
    }
    final shown = items.length < 10 ? items.length : 10;
    final remaining = items.length - shown;
    return '[${[
      for (var i = 0; i < shown; i++) _format(items[i], depth),
      if (remaining == 1) '... 1 more item',
      if (remaining > 1) '... $remaining more items',
    ].join(', ')}]';
  }

  String _object(Map<Object?, Object?> fields, int depth) {
    if (fields.isEmpty) {
      return '{}';
    }
    if (depth > 2) {
      return '[Object]';
    }
    return '{ ${[
      for (final MapEntry(:key, :value) in fields.entries) '$key: ${_format(value, depth)}',
    ].join(', ')} }';
  }
}
