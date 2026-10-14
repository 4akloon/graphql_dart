import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `Boolean`: `true` or `false` (spec §3.5.4).
///
/// {@category scalars}
final class const BooleanCodec() implements ScalarCodec<bool> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<bool> decode(JsonValue json) => switch (json) {
    JsonBool(:final value) => DecodeSuccess(value),
    _ => DecodeFailure('Boolean cannot represent a non boolean value: $json'),
  };

  @override
  JsonValue encode(bool value) => JsonBool(value);
}
