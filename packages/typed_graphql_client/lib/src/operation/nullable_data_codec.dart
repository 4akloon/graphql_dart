import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';

/// Reads and writes a nullable value: JSON `null` is `null`, anything else
/// goes to [item].
///
/// {@category operations}
final class const NullableDataCodec<T extends Object>(
  /// The codec of the non-null values.
  final DataCodec<T> item,
) extends DataCodec<T?> {
  /// Creates the nullable form of [item].
  this;

  @override
  T? read(JsonValue json, DataContext context) => switch (json) {
    JsonNull() => null,
    _ => item.read(json, context),
  };

  @override
  JsonValue write(T? value) => switch (value) {
    null => const JsonNull(),
    final T present => item.write(present),
  };
}
