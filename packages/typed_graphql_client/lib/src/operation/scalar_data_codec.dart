import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';
import 'data_format_exception.dart';

/// Reads and writes a scalar through its [ScalarCodec]: a built-in codec
/// or one the configuration maps a custom scalar to (R7.8).
///
/// {@category operations}
final class const ScalarDataCodec<T>(
  /// The scalar's codec.
  final ScalarCodec<T> codec,
) extends DataCodec<T> {
  /// Creates the codec of the scalar [codec] reads.
  this;

  @override
  T read(JsonValue json, DataContext context) => switch (codec.decode(json)) {
    DecodeSuccess(:final value) => value,
    DecodeFailure(:final message) => throw DataFormatException(message),
  };

  @override
  JsonValue write(T value) => codec.encode(value);
}
