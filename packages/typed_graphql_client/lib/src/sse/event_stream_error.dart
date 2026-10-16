import 'package:meta/meta.dart';

/// Why an event stream cannot be read further; the parser throws it for
/// hostile input and the SSE link turns it into a failure result.
@internal
sealed class EventStreamError implements Exception {
  /// Creates an error.
  const EventStreamError();
}

/// An event, or the line being read, is longer than the limit.
@internal
final class const EventStreamTooLarge(
  /// The limit in bytes.
  final int maxEventBytes,
) extends EventStreamError {
  /// Creates the error.
  this;

  @override
  String toString() => 'An event is longer than $maxEventBytes bytes.';
}

/// The stream's bytes are not UTF-8.
@internal
final class const EventStreamNotUtf8() extends EventStreamError {
  /// Creates the error.
  this;

  @override
  String toString() => 'The event stream is not UTF-8.';
}
