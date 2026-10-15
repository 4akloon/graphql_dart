import 'package:typed_graphql/typed_graphql.dart';

/// Converts the literal of a custom scalar to the JSON its codec decodes
/// when the literal holds variables, as graphql-js's `valueFromASTUntyped`
/// does with the variable values (a non-specified graphql-js behaviour).
///
/// A variable stands for the JSON its already coerced value is made of:
/// null, a boolean, a number, a string, or a list or map of those. A
/// variable without a value is left out of an object and is `null` in a
/// list. A coerced value of any other kind (an enum, an input object
/// decoded to a class) cannot be written back without its type, and is a
/// failure.
///
/// Like [LiteralConverter] it recurses along the literal, and one nested
/// deeper than [JsonReader.maxSupportedDepth] is a failure.
final class VariableLiteralJson {
  /// Converts reading variables from [variables] (the coerced values by
  /// name).
  VariableLiteralJson(this.variables);

  static const LiteralConverter _constants = LiteralConverter();

  /// The coerced variable values.
  final Map<String, Object?> variables;

  /// [literal] as JSON, or a failure.
  DecodeResult<JsonValue> convert(Value literal) => _convert(literal, 0);

  DecodeResult<JsonValue> _convert(Value literal, int depth) {
    if (depth >= JsonReader.maxSupportedDepth) {
      return const DecodeFailure(
        'arrays and objects are nested deeper than '
        '${JsonReader.maxSupportedDepth}',
      );
    }
    return switch (literal) {
      Variable(:final name) => _variable(name.value),
      ListValue(:final values) => _list(values, depth),
      ObjectValue(:final fields) => _object(fields, depth),
      _ => _constants.convert(literal),
    };
  }

  // An absent variable is dropped by the list and the object; reaching
  // here, it is a null, as in a list.
  DecodeResult<JsonValue> _variable(String name) => variables.containsKey(name)
      ? _json(variables[name], name)
      : const DecodeSuccess(JsonNull());

  DecodeResult<JsonValue> _json(Object? value, String name) {
    final converted = _plain(value);
    return converted == null
        ? DecodeFailure(
            'The value of the variable "\$$name" cannot be written as JSON '
            'here.',
          )
        : DecodeSuccess(converted);
  }

  // Null for a value that is not plain data; a Dart null is a JsonNull.
  JsonValue? _plain(Object? value) => switch (value) {
    null => const JsonNull(),
    final bool flag => JsonBool(flag),
    final num number when number.isFinite => JsonNumber(number),
    final String text => JsonString(text),
    final List<Object?> items => _plainList(items),
    final Map<String, Object?> fields => _plainMap(fields),
    _ => null,
  };

  JsonValue? _plainList(List<Object?> items) {
    final converted = <JsonValue>[];
    for (final item in items) {
      final json = _plain(item);
      if (json == null) {
        return null;
      }
      converted.add(json);
    }
    return JsonArray(converted);
  }

  JsonValue? _plainMap(Map<String, Object?> fields) {
    final converted = <String, JsonValue>{};
    for (final MapEntry(:key, :value) in fields.entries) {
      final json = _plain(value);
      if (json == null) {
        return null;
      }
      converted[key] = json;
    }
    return JsonObject(converted);
  }

  DecodeResult<JsonValue> _list(List<Value> values, int depth) {
    final items = <JsonValue>[];
    for (final (index, value) in values.indexed) {
      switch (_convert(value, depth + 1).inside(PathIndex(index))) {
        case DecodeSuccess(value: final item):
          items.add(item);
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonArray(items));
  }

  DecodeResult<JsonValue> _object(List<ObjectField> fields, int depth) {
    final converted = <String, JsonValue>{};
    for (final field in fields) {
      final name = field.name.value;
      final value = field.value;
      if (value is Variable && !variables.containsKey(value.name.value)) {
        continue;
      }
      switch (_convert(value, depth + 1).inside(PathKey(name))) {
        case DecodeSuccess(value: final item):
          converted[name] = item;
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonObject(converted));
  }
}
