import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `ID`: a unique identifier, serialized as a string (spec
/// §3.5.5). A string or an integer decodes, the integer as its decimal
/// text; integers past 2^53 - 1 do not, as the web cannot hold them.
final class const IdCodec() implements ScalarCodec<String> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<String> decode(JsonValue json) => switch (json) {
    JsonString(:final value) => DecodeSuccess(value),
    JsonNumber(:final asInt?) => DecodeSuccess('$asInt'),
    _ => DecodeFailure('ID cannot represent value: $json'),
  };

  @override
  JsonValue encode(String value) => JsonString(value);
}
