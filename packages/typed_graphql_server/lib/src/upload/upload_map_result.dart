import 'package:meta/meta.dart';

import '../http/request_decoding.dart';
import 'upload_map.dart';

/// What reading the `map` field gave: the map, or the refusal to write.
@internal
sealed class UploadMapResult {
  /// Creates a result.
  const UploadMapResult();
}

/// A map that names only null places inside the variables of the operations.
@internal
final class UploadMapValid extends UploadMapResult {
  /// Creates the result holding [map].
  const UploadMapValid(this.map);

  /// The validated map.
  final UploadMap map;
}

/// A map the transport refuses.
@internal
final class UploadMapInvalid extends UploadMapResult {
  /// Creates the result holding [refusal].
  const UploadMapInvalid(this.refusal);

  /// The status, code and message to answer with.
  final DecodingRefusal refusal;
}
