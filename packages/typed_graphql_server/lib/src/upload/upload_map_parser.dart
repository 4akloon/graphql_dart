import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../http/request_decoding.dart';
import 'map_path.dart';
import 'upload_map.dart';
import 'upload_map_entry.dart';
import 'upload_map_result.dart';

/// Reads the `map` field of a multipart request and checks it against the
/// `operations` value (spec section 8 of M7).
///
/// The limits come first, so a map that names thousands of places costs
/// counting, not walking.
@internal
final class UploadMapParser {
  /// Creates a parser that accepts at most [maxFiles] keys and as many paths.
  const UploadMapParser(this.maxFiles);

  /// The most keys, and the most paths in total, the map may hold.
  final int maxFiles;

  static const UploadMapInvalid _malformed = UploadMapInvalid(
    DecodingRefusal(
      400,
      DiagnosticCode.malformedMultipartRequest,
      'The map field must be a JSON object of lists of paths.',
    ),
  );

  static const UploadMapInvalid _badPath = UploadMapInvalid(
    DecodingRefusal(
      400,
      DiagnosticCode.malformedMultipartRequest,
      'A map path must name a null value inside variables.',
    ),
  );

  static const UploadMapInvalid _repeatedPlace = UploadMapInvalid(
    DecodingRefusal(
      400,
      DiagnosticCode.malformedMultipartRequest,
      'Two map paths name the same place.',
    ),
  );

  /// Validates [map] against [operations], never throwing.
  UploadMapResult parse(JsonValue map, JsonValue operations) {
    if (map is! JsonObject) return _malformed;
    if (map.fields.length > maxFiles) return _tooMany('files');
    final entries = <UploadMapEntry>[];
    final places = <String>{};
    var pathCount = 0;
    for (final MapEntry(key: field, value: list) in map.fields.entries) {
      if (list is! JsonArray || list.items.isEmpty) return _malformed;
      pathCount += list.items.length;
      if (pathCount > maxFiles) return _tooMany('paths');
      final paths = <MapPath>[];
      final problem = _collect(list, operations, places, paths);
      if (problem != null) return problem;
      entries.add(UploadMapEntry(field, paths));
    }
    return UploadMapValid(UploadMap(entries));
  }

  // `places` is shared by all keys: two keys may not fill one place either.
  UploadMapInvalid? _collect(
    JsonArray list,
    JsonValue operations,
    Set<String> places,
    List<MapPath> paths,
  ) {
    for (final item in list.items) {
      if (item is! JsonString) return _malformed;
      final path = MapPath(item.value);
      if (!path.isNullIn(operations)) return _badPath;
      if (!places.add(path.place)) return _repeatedPlace;
      paths.add(path);
    }
    return null;
  }

  UploadMapInvalid _tooMany(String noun) => UploadMapInvalid(
    DecodingRefusal(
      413,
      DiagnosticCode.tooManyUploads,
      'The map may name at most $maxFiles $noun.',
    ),
  );
}
