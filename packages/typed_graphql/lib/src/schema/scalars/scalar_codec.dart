import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';

/// Reads and writes the values of one scalar type (spec §3.5; R2.9).
///
/// [decode] takes input, a variable or a literal converted to JSON, and
/// gives a [DecodeFailure] for a value the type cannot represent; it never
/// throws. [encode] writes a result value. A codec is registered by scalar
/// name with the server or the client, not held by `ScalarType`: the
/// schema model has no behaviour.
///
/// {@category scalars}
abstract interface class ScalarCodec<T> {
  /// The value [json] stands for, or a failure that says why it cannot.
  DecodeResult<T> decode(JsonValue json);

  /// [value] as JSON. A value the type cannot represent, which only code
  /// can produce, is an [ArgumentError].
  JsonValue encode(T value);
}
