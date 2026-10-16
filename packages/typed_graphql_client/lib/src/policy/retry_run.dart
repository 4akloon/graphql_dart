import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';

import '../client/client_failure.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import 'guarded_start.dart';
import 'retry_policy.dart';

typedef _Decision = ({LinkResult result, bool isRetried});

/// The attempts of one request for `RetryLink`: it forwards the request,
/// waits after a failure the policy accepts, and forwards it again.
@internal
final class RetryRun {
  /// Creates the run of [_request]; nothing starts before the first listener.
  RetryRun(this._policy, this._random, this._request, this._forward) {
    _controller.onListen = _attempt;
    _controller.onCancel = _stop;
  }

  final RetryPolicy _policy;
  final Random _random;
  final LinkRequest _request;
  final NextLink _forward;
  final StreamController<LinkResult> _controller =
      StreamController<LinkResult>();

  StreamSubscription<Object?>? _subscription;
  Timer? _timer;
  int _attemptCount = 0;
  bool _hasDeliveredPayload = false;

  /// What the caller listens to: the delivered results.
  Stream<LinkResult> get results => _controller.stream;

  void _attempt() {
    _attemptCount++;
    // Every callback of the caller and of the chain runs inside a stream
    // operator, so a throw is an error event for `_abort`, not an
    // exception in the zone.
    _subscription = const GuardedStart().listen<_Decision>(
      () => _forward(_request).transform<LinkResult>(_failuresOfLinks),
      convert: _decide,
      onData: _onDecision,
      onError: _abort,
      onDone: _finish,
    );
  }

  // A link must not fail its stream (spec section 6); an Exception that
  // does arrive is a network failure, an Error is a bug and ends the run.
  final StreamTransformer<LinkResult, LinkResult> _failuresOfLinks =
      StreamTransformer<LinkResult, LinkResult>.fromHandlers(
        handleError: (error, stackTrace, sink) {
          if (error is Exception) {
            sink.add(LinkFailure(NetworkFailure(error)));
          } else {
            sink.addError(error, stackTrace);
          }
        },
      );

  _Decision _decide(LinkResult result) {
    switch (result) {
      case LinkPayload():
        _hasDeliveredPayload = true;
        return (result: result, isRetried: false);
      case LinkFailure(:final failure):
        // A payload already delivered would be delivered twice.
        return (
          result: result,
          isRetried: !_hasDeliveredPayload && _willRetry(failure),
        );
    }
  }

  void _onDecision(_Decision decision) {
    if (decision.isRetried) {
      _wait();
    } else {
      _controller.add(decision.result);
    }
  }

  void _abort(Object error, StackTrace stackTrace) {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _controller.addError(error, stackTrace);
    unawaited(_controller.close());
  }

  bool _willRetry(ClientFailure failure) =>
      _attemptCount < _policy.maxAttempts && _policy.isRetryable(failure);

  /// Drops the failed attempt and forwards the request after the delay of
  /// the retry that is about to start (the first retry is number 0).
  void _wait() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    final delay = _policy.backoff.delayFor(_attemptCount - 1, _random);
    _timer = Timer(delay, () {
      _timer = null;
      _attempt();
    });
  }

  void _finish() {
    _subscription = null;
    unawaited(_controller.close());
  }

  Future<void> _stop() {
    _timer?.cancel();
    _timer = null;
    final cancelled = _subscription?.cancel();
    _subscription = null;
    return cancelled ?? Future<void>.value();
  }
}
