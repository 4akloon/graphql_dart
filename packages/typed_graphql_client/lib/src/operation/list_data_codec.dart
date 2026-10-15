import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';
import 'data_format_exception.dart';

/// Reads and writes a list whose items [item] reads; the list read is
/// unmodifiable.
///
/// {@category operations}
final class const ListDataCodec<T>(
  /// The codec of the items.
  final DataCodec<T> item,
) extends DataCodec<List<T>> {
  /// Creates the list form of [item].
  this;

  @override
  List<T> read(JsonValue json, DataContext context) => switch (json) {
    JsonArray(:final items) => List.unmodifiable([
      for (var index = 0; index < items.length; index++)
        _item(items[index], index, context),
    ]),
    _ => throw DataFormatException('Expected a list, got $json.'),
  };

  T _item(JsonValue json, int index, DataContext context) {
    try {
      return item.read(json, context);
    } on DataFormatException catch (exception) {
      throw exception.inside(PathIndex(index));
    }
  }

  @override
  JsonValue write(List<T> value) =>
      JsonArray([for (final element in value) item.write(element)]);
}
