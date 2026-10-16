import 'package:meta/meta.dart';

import 'byte_limit.dart';

/// The error of a stream that carried more bytes than its [ByteLimit] allows.
@internal
final class ByteLimitExceeded implements Exception {
  /// Creates the error of [origin].
  const ByteLimitExceeded(this.origin);

  /// The limit that was passed; a caller that bounds a field inside a request
  /// tells its own limit from the request's by identity.
  final ByteLimit origin;

  @override
  String toString() => 'ByteLimitExceeded: more than ${origin.limit} bytes';
}
