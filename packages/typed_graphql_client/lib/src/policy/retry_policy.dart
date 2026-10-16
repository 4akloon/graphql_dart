import '../client/client_failure.dart';
import '../link/backoff.dart';

/// When and how often `RetryLink` sends a request again (R8.4).
///
/// {@category policy}
final class const RetryPolicy({
  /// How many times a request is sent in all, the first included.
  final int maxAttempts = 3,

  /// How long to wait before each retry.
  final Backoff backoff = const Backoff(),

  /// Decides whether a failure is worth another attempt; null keeps the
  /// default of [isRetryable].
  final bool Function(ClientFailure failure)? retryIf,
}) {
  /// Creates a policy.
  this;

  /// The HTTP statuses the default decision retries: the request timed
  /// out, the server is overloaded or it failed on its own side.
  static const List<int> retryableStatuses = [408, 429, 500, 502, 503, 504];

  /// Whether [failure] is worth another attempt: [retryIf] when given,
  /// else a network failure, a timeout or a status of [retryableStatuses].
  /// A GraphQL error is not a failure and is never retried.
  bool isRetryable(ClientFailure failure) {
    final decide = retryIf;
    if (decide != null) {
      return decide(failure);
    }
    return switch (failure) {
      NetworkFailure() || RequestTimedOut() => true,
      HttpStatusFailure(:final statusCode) => retryableStatuses.contains(
        statusCode,
      ),
      _ => false,
    };
  }
}
