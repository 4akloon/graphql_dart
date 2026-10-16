import 'package:meta/meta.dart';

/// The failure of an upload storage while it stored a file: a fault of the
/// server, never of the request, so it travels apart from the exceptions that
/// the reader turns into a refusal (a storage that throws a
/// `TimeoutException` is not a slow client).
@internal
final class StorageFailure implements Exception {
  /// Creates the failure caused by [cause].
  const StorageFailure(this.cause);

  /// What the storage threw.
  final Exception cause;

  @override
  String toString() => 'The upload storage failed: $cause';
}
