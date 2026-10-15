import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';

/// Keeps a custom scalar the configuration does not map as its JSON (R7.8:
/// an unmapped custom scalar is a [JsonValue], never `dynamic`).
///
/// {@category operations}
final class const JsonDataCodec() extends DataCodec<JsonValue> {
  /// Creates the codec.
  this;

  @override
  JsonValue read(JsonValue json, DataContext context) => json;

  @override
  JsonValue write(JsonValue value) => value;
}
