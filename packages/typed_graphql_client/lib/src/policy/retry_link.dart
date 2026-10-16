import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import 'idempotent.dart';
import 'retry_policy.dart';
import 'retry_run.dart';

/// Sends a request again when it failed for a reason that may pass (R8.4).
///
/// It retries queries, and mutations whose context has [Idempotent]; a
/// subscription and any other mutation are forwarded unchanged (the
/// WebSocket link reconnects on its own). A GraphQL error is an answer and
/// is delivered. After a failure the policy accepts, the link waits for the
/// policy's backoff and forwards the same request again; the last failure is
/// delivered when the attempts run out. Cancelling the stream cancels the
/// wait and the running attempt.
///
/// The files of an `UploadFiles` entry are sent again on each attempt, since
/// every `UploadFile` reopens its content per attempt. A stream error from
/// the links below that is an [Exception] is turned into a `LinkFailure`
/// holding a `NetworkFailure`, so that the policy can judge it; any other
/// error, and an error thrown by `retryIf`, ends the stream as an error.
///
/// {@category policy}
final class RetryLink extends Link {
  /// Creates a link that follows [policy]; [random] draws the delays and
  /// defaults to a fresh [Random]. A `maxAttempts` below 1 is an
  /// [ArgumentError].
  RetryLink({this.policy = const RetryPolicy(), Random? random})
    : _random = random ?? Random() {
    if (policy.maxAttempts < 1) {
      throw ArgumentError.value(
        policy.maxAttempts,
        'policy.maxAttempts',
        'must be at least 1',
      );
    }
  }

  /// The decisions this link follows.
  final RetryPolicy policy;

  final Random _random;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    if (!_isRetriable(request)) {
      return forward(request);
    }
    return RetryRun(policy, _random, request, forward).results;
  }

  bool _isRetriable(LinkRequest request) => switch (request.type) {
    OperationType.query => true,
    OperationType.mutation => request.context.entry<Idempotent>() != null,
    OperationType.subscription => false,
  };
}
