import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';
import 'data_format_exception.dart';
import 'data_object.dart';

/// Reads and writes a generated class: data, fragment or input object.
///
/// {@category operations}
final class const ObjectDataCodec<T extends DataObject>(
  /// The class's reader, a private constructor of the generated class.
  final T Function(JsonObject json, DataContext context) reader,
) extends DataCodec<T> {
  /// Creates the codec of the class [reader] reads.
  this;

  @override
  T read(JsonValue json, DataContext context) => switch (json) {
    final JsonObject object => reader(object, context),
    _ => throw DataFormatException('Expected an object, got $json.'),
  };

  @override
  JsonValue write(T value) => value.toJson();
}
