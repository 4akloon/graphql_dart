import 'dart:typed_data';

import 'package:meta/meta.dart';

/// How reading a request body ended.
@internal
sealed class BodyReadResult {
  /// Creates a result.
  const BodyReadResult();
}

/// The whole body arrived within the limits.
@internal
final class BodyBytes extends BodyReadResult {
  /// Creates the result with the [bytes] read.
  const BodyBytes(this.bytes);

  /// The body, possibly empty.
  final Uint8List bytes;
}

/// The body is longer than the limit; reading stopped.
@internal
final class BodyTooLarge extends BodyReadResult {
  /// Creates the result.
  const BodyTooLarge();
}

/// The body did not arrive within the time limit; reading stopped.
@internal
final class BodyTimedOut extends BodyReadResult {
  /// Creates the result.
  const BodyTimedOut();
}

/// The host's stream reported an error.
@internal
final class BodyFailed extends BodyReadResult {
  /// Creates the result.
  const BodyFailed();
}
