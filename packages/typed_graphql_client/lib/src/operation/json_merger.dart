import 'package:typed_graphql/typed_graphql.dart';

/// Merges the JSON that several generated classes write for one response
/// object (R7.3).
///
/// A class and the fragments it spreads, or two fragments, may select the
/// same response name with different sub-selections; the written object
/// must hold the fields of both. Objects merge by key, recursively; arrays
/// merge by index, as the reader reads the same list once per selection;
/// a null never replaces a value (a class that does not select a field
/// writes null where its fragment wrote the object); for any other pair the
/// later value wins.
///
/// {@category operations}
final class const JsonMerger() {
  /// Creates the merger.
  this;

  /// The merge of [objects] in order; a null entry (a fragment that was not
  /// selected) is skipped.
  JsonObject merge(List<JsonObject?> objects) {
    var merged = JsonObject(const <String, JsonValue>{});
    for (final JsonObject? object in objects) {
      if (object != null) {
        merged = _mergeObjects(merged, object);
      }
    }
    return merged;
  }

  JsonObject _mergeObjects(JsonObject base, JsonObject extra) {
    final fields = <String, JsonValue>{...base.fields};
    for (final MapEntry<String, JsonValue> entry in extra.fields.entries) {
      final JsonValue? existing = fields[entry.key];
      fields[entry.key] = existing == null
          ? entry.value
          : _mergeValues(existing, entry.value);
    }
    return JsonObject(fields);
  }

  JsonValue _mergeValues(JsonValue base, JsonValue extra) =>
      switch ((base, extra)) {
        (final JsonObject base, final JsonObject extra) => _mergeObjects(
          base,
          extra,
        ),
        (final JsonArray base, final JsonArray extra) => _mergeArrays(
          base,
          extra,
        ),
        (_, JsonNull()) => base,
        _ => extra,
      };

  JsonArray _mergeArrays(JsonArray base, JsonArray extra) {
    final int length = base.items.length > extra.items.length
        ? base.items.length
        : extra.items.length;
    return JsonArray([
      for (var index = 0; index < length; index++)
        if (index >= base.items.length)
          extra.items[index]
        else if (index >= extra.items.length)
          base.items[index]
        else
          _mergeValues(base.items[index], extra.items[index]),
    ]);
  }
}
