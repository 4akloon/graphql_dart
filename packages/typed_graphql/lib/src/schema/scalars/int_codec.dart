import '../../protocol/decode_result.dart';
import '../../protocol/json_inspector.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `Int`: a signed 32-bit integer (spec §3.5.1).
///
/// A whole float such as `3.0` decodes, as on the web; a fraction, a
/// number past the bounds and anything but a number do not. The messages
/// are graphql-js's.
///
/// {@category scalars}
final class const IntCodec() implements ScalarCodec<int> {
  /// Creates the codec.
  this;

  /// The smallest `Int`: -2^31.
  static const int min = -2147483648;

  /// The largest `Int`: 2^31 - 1.
  static const int max = 2147483647;

  @override
  DecodeResult<int> decode(JsonValue json) => switch (json) {
    JsonNumber(:final value) when value % 1 != 0 => DecodeFailure(
      'Int cannot represent non-integer value: ${const JsonInspector().inspect(json)}',
    ),
    JsonNumber(:final value) when value < min || value > max => DecodeFailure(
      'Int cannot represent non 32-bit signed integer value: ${const JsonInspector().inspect(json)}',
    ),
    JsonNumber(:final value) => DecodeSuccess(value.toInt()),
    _ => DecodeFailure(
      'Int cannot represent non-integer value: ${const JsonInspector().inspect(json)}',
    ),
  };

  @override
  JsonValue encode(int value) {
    if (value < min || value > max) {
      throw ArgumentError.value(value, 'value', 'is not a 32-bit integer');
    }
    return JsonNumber(value);
  }
}
