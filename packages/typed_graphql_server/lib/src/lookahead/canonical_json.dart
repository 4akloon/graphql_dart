import 'package:typed_graphql/typed_graphql.dart';

/// Writes a [JsonValue] as compact JSON with the keys of every object in
/// sorted order, so equal values give equal text whatever order they were
/// built in. It walks with an explicit stack: a value nested a thousand
/// levels deep costs no call depth.
final class CanonicalJson {
  /// Creates the writer.
  const CanonicalJson();

  /// The canonical text of [value].
  String write(JsonValue value) {
    final out = StringBuffer();
    final pending = <Object>[value];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case final String text:
          out.write(text);
        case JsonArray(:final items):
          _push(pending, ['[', ..._separated(items), ']']);
        case JsonObject(:final fields):
          final keys = fields.keys.toList()..sort();
          _push(pending, [
            '{',
            ..._separated([
              for (final key in keys) ...['${JsonString(key)}:', fields[key]!],
            ], pairs: true),
            '}',
          ]);
        case final JsonValue leaf:
          out.write(leaf);
        case final Object other:
          throw StateError('Unexpected canonical JSON part $other.');
      }
    }
    return out.toString();
  }

  // Parts in reading order; pushed reversed so they pop in that order.
  void _push(List<Object> pending, List<Object> parts) {
    for (var i = parts.length - 1; i >= 0; i--) {
      pending.add(parts[i]);
    }
  }

  // Commas between the items, or between the key/value pairs.
  List<Object> _separated(List<Object> items, {bool pairs = false}) {
    final step = pairs ? 2 : 1;
    return [
      for (var i = 0; i < items.length; i += step) ...[
        if (i > 0) ',',
        for (var j = i; j < i + step; j++) items[j],
      ],
    ];
  }
}
