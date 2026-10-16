import 'dart:async';

import '../client/client_failure.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import 'token_renewal.dart';

/// The attempts of one request for `AuthLink`: the request with the token,
/// and once more with a renewed token when the first answer is a 401.
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
  StreamSubscription<LinkResult>? _subscription;
  bool _isCancelled = false;

  /// What the caller listens to: the answer of the attempt that was kept.
  Stream<LinkResult> get results => _controller.stream;

  Future<void> _begin() async {
    final String? token;
    try {
      token = await renewal.current();
    } on Exception catch (exception) {
      _fail(exception);
      return;
    } on Object catch (error, stackTrace) {
      _abort(error, stackTrace);
      return;
    }
    _send(token, isRetry: false);
  }

  void _send(String? token, {required bool isRetry}) {
    if (_isCancelled) {
      return;
    }
    _subscription = forward(authorize(request, token)).listen(
      (result) => _onResult(result, token, isRetry: isRetry),
      onError: _controller.addError,
      onDone: () {
        _subscription = null;
        unawaited(_controller.close());
      },
    );
  }

  void _onResult(
    LinkResult result,
    String? sentToken, {
    required bool isRetry,
  }) {
    final bool isRefused;
    try {
      isRefused = !isRetry && renewal.canRefresh && isUnauthorized(result);
    } on Object catch (error, stackTrace) {
      // The caller's `isUnauthorized` threw: deliver it, or the stream hangs.
      _abort(error, stackTrace);
      return;
    }
    if (isRefused) {
      unawaited(_renew(result, sentToken));
    } else {
      _controller.add(result);
    }
  }

  /// Drops the refused attempt and sends the request again with a renewed
  /// token; with none, [refused] is the answer.
  Future<void> _renew(LinkResult refused, String? sentToken) async {
    unawaited(_subscription?.cancel());
    _subscription = null;
    final String? token;
    try {
      token = await renewal.renewed(sentToken);
    } on Exception catch (exception) {
      _fail(exception);
      return;
    } on Object catch (error, stackTrace) {
      _abort(error, stackTrace);
      return;
    }
    if (token == null) {
      _deliverAndEnd(refused);
    } else {
      _send(token, isRetry: true);
    }
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
