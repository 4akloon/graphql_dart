import 'dart:convert';

/// A JSON value: the type of arbitrary JSON in the public API (R0.2).
///
/// A sealed family, so a `switch` over it is exhaustive. Values are
/// immutable and compare by value: arrays item by item, objects by keys
/// and values whatever their order. Every number is one [JsonNumber],
/// because the web cannot tell `1` from `1.0`. Untrusted input becomes a
/// [JsonValue] through `JsonReader`, never by a cast.
sealed class const JsonValue() {
  /// Creates a value.
  this;

  /// This value as plain Dart objects (`null`, `bool`, `num`, `String`,
  /// `List<Object?>`, `Map<String, Object?>`), which `jsonEncode` writes.
  Object? toJson();

  /// This value as compact JSON text.
  @override
  String toString() => jsonEncode(toJson());
}

/// The JSON `null`.
final class const JsonNull() extends JsonValue {
  /// Creates the JSON `null`.
  this;

  @override
  Null toJson() => null;

  @override
  bool operator ==(Object other) => other is JsonNull;

  @override
  int get hashCode => null.hashCode;
}

/// `true` or `false`.
final class const JsonBool(
  /// The boolean.
  final bool value,
) extends JsonValue {
  /// Creates a boolean.
  this;

  @override
  bool toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonBool && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A finite number.
///
/// `1` and `1.0` are equal, as they are on the web. [asInt] reads a whole
/// number the same way on every platform.
final class JsonNumber(
  /// The number; never NaN or infinite.
  final num value,
) extends JsonValue {
  /// Creates a number; NaN and the infinities are an [ArgumentError], JSON
  /// cannot write them.
  this {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'is not a finite number');
    }
  }

  /// The largest integer every platform holds exactly: 2^53 - 1.
  static const int maxSafeInteger = 9007199254740991;

  /// [value] as an `int` when it is a whole number no larger in magnitude
  /// than [maxSafeInteger]; otherwise null.
  ///
  /// The bound gives the same answer on every platform: past it the web
  /// has already rounded the number, the VM has not.
  int? get asInt {
    if (value % 1 != 0 || value < -maxSafeInteger || value > maxSafeInteger) {
      return null;
    }
    return value.toInt();
  }

  @override
  num toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A string.
final class const JsonString(
  /// The string.
  final String value,
) extends JsonValue {
  /// Creates a string.
  this;

  @override
  String toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonString && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// An array.
final class JsonArray(List<JsonValue> items) extends JsonValue {
  /// Creates an array of a copy of [items].
  this;

  /// The items, in order; the list cannot be modified.
  final List<JsonValue> items = List.unmodifiable(items);

  @override
  List<Object?> toJson() => [for (final item in items) item.toJson()];

  @override
  bool operator ==(Object other) {
    if (other is! JsonArray || other.items.length != items.length) {
      return false;
    }
    for (var i = 0; i < items.length; i++) {
      if (other.items[i] != items[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(items);
}

/// An object: string keys in their order of insertion, each with a value.
final class JsonObject(Map<String, JsonValue> fields) extends JsonValue {
  /// Creates an object of a copy of [fields].
  this;

  /// The keys and values, in order; the map cannot be modified.
  final Map<String, JsonValue> fields = Map.unmodifiable(fields);

  /// The value at [key], or null when the object has no such key (a JSON
  /// `null` is a [JsonNull]).
  JsonValue? operator [](String key) => fields[key];

  @override
  Map<String, Object?> toJson() => {
    for (final MapEntry(:key, :value) in fields.entries) key: value.toJson(),
  };

  @override
  bool operator ==(Object other) {
    if (other is! JsonObject || other.fields.length != fields.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in fields.entries) {
      if (other.fields[key] != value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final MapEntry(:key, :value) in fields.entries)
      Object.hash(key, value),
  ]);
}
