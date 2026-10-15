import 'package:typed_graphql/typed_graphql.dart';

/// What `ExecutableSchema.subscribe` answers: a stream of results, or a
/// request error and no stream.
///
/// {@category execution}
sealed class SubscriptionResult {
  const SubscriptionResult();
}

/// The subscription started.
///
/// [results] is a single-subscription stream: the source is listened to when
/// [results] is, pausing and resuming pass through to the source, and
/// cancelling the subscription to [results] cancels the source. It closes
/// when the source is done.
///
/// {@category execution}
final class SubscriptionStarted extends SubscriptionResult {
  /// Wraps [results].
  const SubscriptionStarted(this.results);

  /// One result per source event, in order.
  final Stream<ExecutionResult> results;
}

/// The subscription did not start: a request error, or the source stream
/// could not be created (September2025 6.2.3.1), as graphql-js answers with
/// a result of errors instead of a stream.
///
/// {@category execution}
final class SubscriptionRejected extends SubscriptionResult {
  /// Wraps [error].
  const SubscriptionRejected(this.error);

  /// The errors, as the response to the request.
  final RequestErrorResult error;
}
