import 'dart:math';

import 'package:meta/meta.dart';

import '../link/backoff.dart';

/// When `WebSocketLink` tries a lost connection again, and how long it
/// waits (R8.4), after graphql-ws's reference client.
@internal
final class ReconnectPolicy({
  /// How many failed attempts in a row are tried again.
  required final int retryAttempts,

  /// The wait before each retry.
  required final Backoff backoff,

  /// The source of the backoff's jitter.
  required final Random random,
}) {
  /// Creates the policy.
  this;

  /// Close codes the reference client never retries: its own errors
  /// (`4500`, `4005`), a bad request or response (`4400`, `4004`), a
  /// refused or conflicting one (`4401`, `4406`, `4409`, `4429`).
  ///
  /// `4403` (forbidden) and `4504` stay retryable, as there: the access
  /// may be granted, or the server may answer in time, on the next try. That
  /// is about a 4504 *sent by a server*. The link's own acknowledgement
  /// timeout fails the operations with `GQL472` and does not reconnect: it is
  /// reported as `AckTimedOut`, which never reaches this policy.
  static const Set<int> _neverRetried = {
    4500,
    4005,
    4400,
    4004,
    4401,
    4406,
    4409,
    4429,
  };

  /// The `1xxx` codes that mean "try again": a normal end, a server going
  /// away or restarting, an abnormal close. Every other `1xxx` code is the
  /// WebSocket layer reporting an error that a retry would repeat.
  static const Set<int> _retriedInternal = {
    1000,
    1001,
    1005,
    1006,
    1012,
    1013,
    1014,
  };

  /// Whether a socket closed with [code] is never connected again.
  bool isFatal(int? code) {
    if (code == null) {
      return false;
    }
    if (_neverRetried.contains(code)) {
      return true;
    }
    return code >= 1000 && code <= 1999 && !_retriedInternal.contains(code);
  }

  /// Whether [failedAttempts] failures in a row (from 1) may be followed
  /// by another try.
  bool allowsRetry(int failedAttempts) => failedAttempts <= retryAttempts;

  /// The wait after [failedAttempts] failures in a row (from 1).
  Duration delayFor(int failedAttempts) =>
      backoff.delayFor(failedAttempts - 1, random);
}
