import '../../protocol/decode_result.dart';
import '../../protocol/json_inspector.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `Float`: a finite double (spec §3.5.2). Any JSON number
/// decodes, as JSON has no NaN or infinity.
///
/// {@category scalars}
final class const FloatCodec() implements ScalarCodec<double> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<double> decode(JsonValue json) => switch (json) {
    JsonNumber(:final value) => DecodeSuccess(value.toDouble()),
    _ => DecodeFailure(
      'Float cannot represent non numeric value: ${const JsonInspector().inspect(json)}',
    ),
  };

  @override
  JsonValue encode(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'is not a finite number');
    }
    return JsonNumber(value);
  }
}
