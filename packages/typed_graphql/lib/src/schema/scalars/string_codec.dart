import '../../protocol/decode_result.dart';
import '../../protocol/json_inspector.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `String`: Unicode text (spec §3.5.3).
///
/// {@category scalars}
final class const StringCodec() implements ScalarCodec<String> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<String> decode(JsonValue json) => switch (json) {
    JsonString(:final value) => DecodeSuccess(value),
    _ => DecodeFailure(
      'String cannot represent a non string value: ${const JsonInspector().inspect(json)}',
    ),
  };

  @override
  JsonValue encode(String value) => JsonString(value);
}
