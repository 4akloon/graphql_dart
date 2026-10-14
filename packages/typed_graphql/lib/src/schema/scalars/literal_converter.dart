import '../../language/ast/object_field.dart';
import '../../language/ast/value.dart';
import '../../protocol/decode_result.dart';
import '../../protocol/json_reader.dart';
import '../../protocol/json_value.dart';
import '../../protocol/path_segment.dart';
import 'scalar_codec.dart';

/// Converts a constant literal to the JSON a [ScalarCodec] decodes, so a
/// codec needs no `parseLiteral` (spec §6).
///
/// An enum value becomes its name, as graphql-js's
/// `valueFromASTUntyped`; of two object fields with one name the last
/// wins (validation reports the repeat). A variable and a number too large
/// to be finite are failures, with the path to them, and so is nesting deeper
/// than [JsonReader.maxSupportedDepth] (the conversion recurses, and the web
/// stack is shallow). An integer beyond 2^53 becomes a double on the web;
/// on the VM it stays exact up to 2^63 and becomes a double beyond that.
/// [JsonNumber.asInt] is the safe view.
///
/// {@category scalars}
final class const LiteralConverter() {
  /// Creates a converter.
  this;

  /// [value] as JSON, or a failure.
  DecodeResult<JsonValue> convert(Value value) => _convert(value, 0);

  DecodeResult<JsonValue> _convert(Value value, int depth) => switch (value) {
    IntValue(value: final text) || FloatValue(value: final text) => _number(
      text,
    ),
    StringValue(value: final text) => DecodeSuccess(JsonString(text)),
    BooleanValue(value: final flag) => DecodeSuccess(JsonBool(flag)),
    NullValue() => const DecodeSuccess(JsonNull()),
    EnumValue(value: final name) => DecodeSuccess(JsonString(name)),
    ListValue() when depth >= JsonReader.maxSupportedDepth => _tooDeep(),
    ObjectValue() when depth >= JsonReader.maxSupportedDepth => _tooDeep(),
    ListValue(:final values) => _list(values, depth),
    ObjectValue(:final fields) => _object(fields, depth),
    Variable(:final name) => DecodeFailure(
      'The variable "\$${name.value}" has no value here.',
    ),
  };

  DecodeFailure _tooDeep() => const DecodeFailure(
    'arrays and objects are nested deeper than ${JsonReader.maxSupportedDepth}',
  );

  // `num.tryParse` also reads `0x1F`, `NaN` and padded text, which no
  // GraphQL number lexeme is: the lexeme shape is checked first.
  static final RegExp _lexeme = RegExp(
    r'^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$',
  );

  DecodeResult<JsonValue> _number(String text) {
    final number = _lexeme.hasMatch(text) ? num.tryParse(text) : null;
    return switch (number) {
      null => DecodeFailure('"$text" is not a number.'),
      _ when number.isFinite => DecodeSuccess(JsonNumber(number)),
      _ => DecodeFailure('The number $text is too large.'),
    };
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
      switch (_convert(field.value, depth + 1).inside(PathKey(name))) {
        case DecodeSuccess(:final value):
          converted[name] = value;
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonObject(converted));
  }
}
