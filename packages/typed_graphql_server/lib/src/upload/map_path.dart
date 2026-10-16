import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// A place inside an `operations` value, written as the multipart request
/// specification writes it: segments joined by `.`.
///
/// A path names a place in the variables only: `variables.a.0` in a request,
/// `2.variables.a.0` in a batch. A segment is an object key or, for an array,
/// a decimal index with no sign and no leading zero.
@internal
final class MapPath {
  /// Creates the path of [text].
  MapPath(String text) : segments = text.split('.');

  static final RegExp _index = RegExp(r'^(0|[1-9][0-9]*)$');

  /// The keys and indices to follow from the root.
  final List<String> segments;

  /// The path as it was written, which is how two paths name one place.
  String get place => segments.join('.');

  /// Whether the path leads to an existing `null` inside the variables of
  /// [operations].
  bool isNullIn(JsonValue operations) {
    if (!_startsInVariables(operations)) return false;
    var node = operations;
    for (final segment in segments) {
      final child = _child(node, segment);
      if (child == null) return false;
      node = child;
    }
    return node is JsonNull;
  }

  /// A copy of [operations] with [replacement] at this path; the other values
  /// are shared with [operations]. The path must pass [isNullIn].
  ///
  /// It recurses once per segment, and a path that passed [isNullIn] is no
  /// longer than the nesting of the JSON it names.
  JsonValue replace(JsonValue operations, JsonValue replacement) =>
      _replaceAt(operations, 0, replacement);

  JsonValue _replaceAt(JsonValue node, int depth, JsonValue replacement) {
    if (depth == segments.length) return replacement;
    final segment = segments[depth];
    return switch (node) {
      JsonObject(:final fields) => JsonObject({
        ...fields,
        segment: _replaceAt(
          fields[segment] ?? const JsonNull(),
          depth + 1,
          replacement,
        ),
      }),
      JsonArray(:final items) => _replaceItem(items, depth, replacement),
      _ => node,
    };
  }

  JsonArray _replaceItem(
    List<JsonValue> items,
    int depth,
    JsonValue replacement,
  ) {
    final target = int.parse(segments[depth]);
    return JsonArray([
      for (final (index, item) in items.indexed)
        if (index == target) _replaceAt(item, depth + 1, replacement) else item,
    ]);
  }

  bool _startsInVariables(JsonValue operations) => switch (operations) {
    JsonObject() => segments.length >= 2 && segments.first == 'variables',
    JsonArray(:final items) =>
      segments.length >= 3 &&
          _indexOf(segments.first, items.length) != null &&
          segments[1] == 'variables',
    _ => false,
  };

  JsonValue? _child(JsonValue node, String segment) => switch (node) {
    JsonObject(:final fields) => fields[segment],
    JsonArray(:final items) => _itemAt(items, segment),
    _ => null,
  };

  JsonValue? _itemAt(List<JsonValue> items, String segment) {
    final index = _indexOf(segment, items.length);
    return index == null ? null : items[index];
  }

  int? _indexOf(String segment, int length) {
    if (!_index.hasMatch(segment)) return null;
    final index = int.tryParse(segment);
    return index != null && index < length ? index : null;
  }
}
