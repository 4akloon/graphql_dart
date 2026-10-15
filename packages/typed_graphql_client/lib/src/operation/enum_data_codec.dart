import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';
import 'data_enum.dart';
import 'data_format_exception.dart';

/// Reads and writes a generated enum by its GraphQL name (R7.6).
///
/// {@category operations}
final class const EnumDataCodec<T extends DataEnum>(
  /// The enum's `parse` constructor: the known value of a name, or the
  /// unknown value that keeps it.
  final T Function(String raw) parse,
) extends DataCodec<T> {
  /// Creates the codec of the enum [parse] reads.
  this;

  @override
  T read(JsonValue json, DataContext context) => switch (json) {
    JsonString(:final value) => parse(value),
    _ => throw DataFormatException('Expected an enum value name, got $json.'),
  };

  @override
  JsonValue write(T value) => JsonString(value.raw);
}
