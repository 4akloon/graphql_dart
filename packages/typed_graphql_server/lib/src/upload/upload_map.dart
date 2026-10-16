import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'upload_map_entry.dart';

/// The `map` field of a multipart request, validated against its
/// `operations`: which file part goes to which places.
@internal
final class UploadMap {
  /// Creates a map of [entries], in the order of the `map` field.
  const UploadMap(this.entries);

  /// The file parts the map names.
  final List<UploadMapEntry> entries;

  /// A copy of [operations] with every mapped place replaced by the token of
  /// its file, which [tokenByField] gives for each part name.
  ///
  /// A part without a token is a [StateError]: the reader has all the files
  /// before it applies the map.
  JsonValue apply(JsonValue operations, Map<String, String> tokenByField) {
    var result = operations;
    for (final UploadMapEntry(:field, :paths) in entries) {
      final token = tokenByField[field];
      if (token == null) throw StateError('No token for the part "$field".');
      for (final path in paths) {
        result = path.replace(result, JsonString(token));
      }
    }
    return result;
  }
}
