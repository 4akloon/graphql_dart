import 'dart:async';
import 'dart:math';

import '../client/client_failure.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import 'retry_policy.dart';

/// The attempts of one request for `RetryLink`: it forwards the request,
/// waits after a failure the policy accepts, and forwards it again.
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

  StreamSubscription<LinkResult>? _subscription;
  Timer? _timer;
  int _attemptCount = 0;

  /// What the caller listens to: the delivered results.
  Stream<LinkResult> get results => _controller.stream;

  void _attempt() {
    _attemptCount++;
    _subscription = _forward(
      _request,
    ).listen(_onResult, onError: _onError, onDone: _finish);
  }

  void _onResult(LinkResult result) {
    if (result case LinkFailure(:final failure)) {
      final bool isRetried;
      try {
        isRetried = _willRetry(failure);
      } on Object catch (error, stackTrace) {
        // The caller's `retryIf` threw: deliver it, or the stream would hang.
        _abort(error, stackTrace);
        return;
      }
      if (isRetried) {
        _wait();
        return;
      }
    }
    _controller.add(result);
  }

  void _abort(Object error, StackTrace stackTrace) {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _controller.addError(error, stackTrace);
    unawaited(_controller.close());
  }

  // A link must not fail its stream (spec section 6); an Exception that
  // does arrive is a network failure, an Error is a bug and passes on.
  void _onError(Object error, StackTrace stackTrace) {
    if (error is Exception) {
      _onResult(LinkFailure(NetworkFailure(error)));
    } else {
      _controller.addError(error, stackTrace);
    }
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
