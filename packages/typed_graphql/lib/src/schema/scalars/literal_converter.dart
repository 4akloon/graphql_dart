import '../../language/ast/object_field.dart';
import '../../language/ast/value.dart';
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import '../../protocol/path_segment.dart';
import 'scalar_codec.dart';

/// Converts a constant literal to the JSON a [ScalarCodec] decodes, so a
/// codec needs no `parseLiteral` (spec §6).
///
/// An enum value becomes its name, as graphql-js's
/// `valueFromASTUntyped`; of two object fields with one name the last
/// wins (validation reports the repeat). A variable and a number too large
/// to be finite are failures, with the path to them.
final class const LiteralConverter() {
  /// Creates a converter.
  this;

  /// [value] as JSON, or a failure.
  DecodeResult<JsonValue> convert(Value value) => switch (value) {
    IntValue(value: final text) || FloatValue(value: final text) => _number(
      text,
    ),
    StringValue(value: final text) => DecodeSuccess(JsonString(text)),
    BooleanValue(value: final flag) => DecodeSuccess(JsonBool(flag)),
    NullValue() => const DecodeSuccess(JsonNull()),
    EnumValue(value: final name) => DecodeSuccess(JsonString(name)),
    ListValue(:final values) => _list(values),
    ObjectValue(:final fields) => _object(fields),
    Variable(:final name) => DecodeFailure(
      'The variable "\$${name.value}" has no value here.',
    ),
  };

  DecodeResult<JsonValue> _number(String text) => switch (num.tryParse(text)) {
    final number? when number.isFinite => DecodeSuccess(JsonNumber(number)),
    final _? => DecodeFailure('The number $text is too large.'),
    null => DecodeFailure('"$text" is not a number.'),
  };

  DecodeResult<JsonValue> _list(List<Value> values) {
    final items = <JsonValue>[];
    for (final (index, value) in values.indexed) {
      switch (convert(value).inside(PathIndex(index))) {
        case DecodeSuccess(value: final item):
          items.add(item);
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonArray(items));
  }

  DecodeResult<JsonValue> _object(List<ObjectField> fields) {
    final converted = <String, JsonValue>{};
    for (final field in fields) {
      final name = field.name.value;
      switch (convert(field.value).inside(PathKey(name))) {
        case DecodeSuccess(:final value):
          converted[name] = value;
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonObject(converted));
  }
}
