import 'package:meta/meta.dart';

/// The failure of a request body that the host's stream reported, or that
/// the client's going away caused; [cause] is null for the latter.
@internal
final class BodyFailure implements Exception {
  /// Creates the failure caused by [cause].
  const BodyFailure([this.cause]);

  /// What the host's stream failed with, if anything.
  final Object? cause;
}
