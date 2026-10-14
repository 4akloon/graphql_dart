import 'decode_result.dart';
import 'json_value.dart';
import 'path_segment.dart';

/// Reads the fields of one [JsonObject] by key; a missing or mistyped
/// field is a [DecodeFailure] placed inside its key.
///
/// The optional readers treat an absent key and a JSON `null` alike, as
/// GraphQL's request and response formats do.
final class JsonFieldReader(
  /// The object whose fields are read.
  final JsonObject object,
) {
  /// Creates a reader of [object].
  this;

  /// The string at [key], which must be present.
  DecodeResult<String> string(String key) => switch (object[key]) {
    JsonString(:final value) => DecodeSuccess(value),
    null => const DecodeFailure('is required').inside(PathKey(key)),
    _ => const DecodeFailure('expected a string').inside(PathKey(key)),
  };

  /// The string at [key], or null when it is absent or `null`.
  DecodeResult<String?> optionalString(String key) => switch (object[key]) {
    null || JsonNull() => const DecodeSuccess(null),
    JsonString(:final value) => DecodeSuccess(value),
    _ => const DecodeFailure('expected a string').inside(PathKey(key)),
  };

  /// The object at [key], or null when it is absent or `null`.
  DecodeResult<JsonObject?> optionalObject(String key) => switch (object[key]) {
    null || JsonNull() => const DecodeSuccess(null),
    final JsonObject value => DecodeSuccess(value),
    _ => const DecodeFailure('expected an object').inside(PathKey(key)),
  };

  /// The array at [key] with every item read by [decode], or null when it
  /// is absent or `null`; the first bad item is the failure.
  DecodeResult<List<T>?> optionalList<T>(
    String key,
    DecodeResult<T> Function(JsonValue item) decode,
  ) => switch (object[key]) {
    null || JsonNull() => DecodeSuccess<List<T>?>(null),
    JsonArray(:final items) => _readAll(items, decode).inside(PathKey(key)),
    _ => const DecodeFailure('expected an array').inside(PathKey(key)),
  };

  /// Every item of [items] read by [decode], or the first failure.
  DecodeResult<List<T>> _readAll<T>(
    List<JsonValue> items,
    DecodeResult<T> Function(JsonValue item) decode,
  ) {
    final values = <T>[];
    for (var i = 0; i < items.length; i++) {
      switch (decode(items[i]).inside(PathIndex(i))) {
        case DecodeSuccess(:final value):
          values.add(value);
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(List.unmodifiable(values));
  }
}
