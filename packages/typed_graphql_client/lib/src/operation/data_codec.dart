import 'package:typed_graphql/typed_graphql.dart';

import 'data_context.dart';
import 'data_format_exception.dart';

/// Reads one kind of value of a response from JSON and writes it back: the
/// building block of generated data classes (R7.3).
///
/// Generated code composes the kinds as constants, such as
/// `ListDataCodec(NullableDataCodec(UserCard.codec))` for `[UserCard]`.
/// [read] throws a [DataFormatException] for a value of the wrong shape;
/// [decode] turns it into a [DecodeFailure] with the path, so bad input
/// never escapes as an exception (R0.3).
///
/// {@category operations}
abstract base class DataCodec<T> {
  /// Creates a codec.
  const DataCodec();

  /// Reads [json]; throws a [DataFormatException] when it has the wrong
  /// shape.
  T read(JsonValue json, DataContext context);

  /// Writes [value] as the JSON [read] reads back.
  JsonValue write(T value);

  /// Reads the member [key] of [object]; a missing member reads as `null`,
  /// as a field skipped by `@skip` or `@include`.
  T field(JsonObject object, String key, DataContext context) {
    try {
      return read(object[key] ?? const JsonNull(), context);
    } on DataFormatException catch (exception) {
      throw exception.inside(PathKey(key));
    }
  }

  /// Reads the member [key] of [object], absent when [object] has no such
  /// member (input objects, R7.7).
  Optional<T> optionalField(
    JsonObject object,
    String key,
    DataContext context,
  ) => switch (object[key]) {
    null => const Optional.absent(),
    _ => Optional.present(field(object, key, context)),
  };

  /// Reads [json] and returns the value, or the problem and its path.
  DecodeResult<T> decode(
    JsonValue json, [
    DataContext context = const DataContext(),
  ]) {
    try {
      return DecodeSuccess(read(json, context));
    } on DataFormatException catch (exception) {
      return DecodeFailure(exception.message, path: exception.path);
    }
  }
}
