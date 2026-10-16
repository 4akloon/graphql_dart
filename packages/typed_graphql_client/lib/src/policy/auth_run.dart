import 'dart:async';

import 'package:meta/meta.dart';

import '../client/client_failure.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import 'guarded_start.dart';
import 'token_renewal.dart';

typedef _Judged = ({LinkResult result, bool isRefused});

/// The attempts of one request for `AuthLink`: the request with the token,
/// and once more with a renewed token when the first answer is a 401.
@internal
final class AuthRun {
  /// Creates the run of [request]; nothing starts before the first listener.
  /// [authorize] gives the request with a token's header.
  AuthRun(
    this.request,
    this.forward, {
    required this.renewal,
    required this.authorize,
    required this.isUnauthorized,
  }) {
    _controller.onListen = _begin;
    _controller.onCancel = _stop;
  }

  /// The request as the caller made it.
  final LinkRequest request;

  /// Sends a request to the rest of the chain.
  final NextLink forward;

  /// Reads and renews the token.
  final TokenRenewal renewal;

  /// The request with the header of a token (null: no header).
  final LinkRequest Function(LinkRequest request, String? token) authorize;

  /// Whether a result says the token was refused.
  final bool Function(LinkResult result) isUnauthorized;

  final StreamController<LinkResult> _controller =
      StreamController<LinkResult>();
  StreamSubscription<Object?>? _subscription;
  bool _isCancelled = false;

  /// What the caller listens to: the answer of the attempt that was kept.
  Stream<LinkResult> get results => _controller.stream;

  void _begin() {
    unawaited(
      renewal.current().then(
        (token) => _send(token, isRetry: false),
        onError: _onTokenError,
      ),
    );
  }

  // `then` with `onError` sees what a callback of the caller threw, an
  // Exception or not, without a catch clause.
  void _onTokenError(Object error, StackTrace stackTrace) {
    if (error is Exception) {
      _fail(error);
    } else {
      _abort(error, stackTrace);
    }
  }

  void _send(String? token, {required bool isRetry}) {
    if (_isCancelled) {
      return;
    }
    // The chain, `authorize` and `isUnauthorized` run inside stream
    // operators: a throw is an error event for `_abort`.
    _subscription = const GuardedStart().listen<_Judged>(
      () => forward(authorize(request, token)),
      convert: (result) => _judge(result, isRetry: isRetry),
      onData: (judged) => _onResult(judged, token),
      onError: _abort,
      onDone: () {
        _subscription = null;
        unawaited(_controller.close());
      },
    );
  }

  _Judged _judge(
    LinkResult result, {
    required bool isRetry,
  }) => (
    result: result,
    isRefused: !isRetry && renewal.canRefresh && isUnauthorized(result),
  );

  void _onResult(_Judged judged, String? sent) {
    if (judged.isRefused) {
      _renew(judged.result, sent);
    } else {
      _controller.add(judged.result);
    }
  }

  /// Drops the refused attempt and sends the request again with a renewed
  /// token; with none, [refused] is the answer.
  void _renew(LinkResult refused, String? sentToken) {
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(
      renewal
          .renewed(sentToken)
          .then(
            (token) => token == null
                ? _deliverAndEnd(refused)
                : _send(token, isRetry: true),
            onError: _onTokenError,
          ),
    );
  }

  void _fail(Exception exception) =>
      _deliverAndEnd(LinkFailure(AuthenticationFailure(exception)));

  /// Ends the run with a stream error and cancels the running attempt; for
  /// what is not an [Exception], which is a bug and must not be hidden.
  void _abort(Object error, StackTrace stackTrace) {
    if (_isCancelled) {
      return;
    }
    unawaited(_subscription?.cancel());
    _subscription = null;
    _controller.addError(error, stackTrace);
    unawaited(_controller.close());
  }

  void _deliverAndEnd(LinkResult result) {
    if (_isCancelled) {
      return;
    }
    _controller.add(result);
    unawaited(_controller.close());
  }

  Future<void> _stop() {
    _isCancelled = true;
    final cancelled = _subscription?.cancel();
    _subscription = null;
    return cancelled ?? Future<void>.value();
  }
}
