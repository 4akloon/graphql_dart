import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Writes a [JsonValue] as the UTF-8 bytes of its JSON text.
@internal
final class JsonBytes {
  /// Creates the writer.
  const JsonBytes();

  /// The UTF-8 bytes of [json].
  List<int> of(JsonValue json) => utf8.encode(jsonEncode(json.toJson()));
}
