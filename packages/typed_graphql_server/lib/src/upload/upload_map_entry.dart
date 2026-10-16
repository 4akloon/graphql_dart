import 'package:meta/meta.dart';

import 'map_path.dart';

/// One key of the `map` field: the name of a file part and the places in the
/// operations that receive that file.
@internal
final class UploadMapEntry {
  /// Creates the entry of the part named [field], received at [paths].
  const UploadMapEntry(this.field, this.paths);

  /// The name of the file part.
  final String field;

  /// The places that hold the file, at least one.
  final List<MapPath> paths;
}
