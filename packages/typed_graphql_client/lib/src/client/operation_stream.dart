import 'dart:async';

import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import 'cancel_token.dart';
import 'client_failure.dart';
import 'graphql_response.dart';
import 'response_decoder.dart';

/// The typed responses of one request: it calls the link chain when
/// listened to, decodes each result, and ends with [RequestCancelled] when
/// the caller's token fires (spec sections 4 and 7).
final class OperationStream<D extends Object> {
  /// Creates the stream of [_request] through [_link].
  OperationStream(
    this._link,
    this._request,
    this._decoder,
    this._cancelToken,
  );

  final Link _link;
  final LinkRequest _request;
  final ResponseDecoder<D> _decoder;
  final CancelToken? _cancelToken;

  // `late` because the initializer reads `_start` and `_stop`, which a
  // field initializer cannot reference through `this`.
  late final StreamController<GraphQLResponse<D>> _controller =
      StreamController(
        onListen: _start,
        onCancel: _stop,
        onPause: () => _subscription?.pause(),
        onResume: () => _subscription?.resume(),
      );
  StreamSubscription<GraphQLResponse<D>>? _subscription;
  void Function()? _removeListener;

  /// The responses; single-subscription.
  Stream<GraphQLResponse<D>> get stream => _controller.stream;

  void _start() {
    final token = _cancelToken;
    if (token != null && token.isCancelled) {
      _cancel(token);
      return;
    }
    // Set before listening: a synchronous link may end inside `listen`.
    _removeListener = token?.addListener(() => _cancel(token));
    // `asyncExpand` and `map` call the link and the decoder inside the
    // stream's own try/catch: an error either throws, such as a bug in a
    // link or in generated code, reaches `_fail` as an error event instead
    // of escaping `listen` or the data callback. The repo rules forbid
    // catching `Error`, so no `catch` here does it. The controller is
    // synchronous so that a link still starts inside `listen`.
    final requests = StreamController<LinkRequest>(sync: true);
    _subscription = requests.stream
        .asyncExpand((request) => _link.request(request, _unterminated))
        .map(_decoder.decode)
        .listen(_controller.add, onError: _fail, onDone: _finish);
    requests
      ..add(_request)
      ..close();
  }

  /// Cancels the link chain's stream without returning its cancel future:
  /// a returned one would make the caller wait on a root-zone future, so
  /// under fake time a response would only arrive on the real event loop.
  void _stop() {
    _removeListener?.call();
    _removeListener = null;
    unawaited(_subscription?.cancel());
  }

  void _cancel(CancelToken token) {
    _stop();
    _controller.add(GraphQLTransportFailure(RequestCancelled(token.reason)));
    _finish();
  }

  /// A link stream that broke the rule and emitted an error: an
  /// [Exception] is a network failure, anything else a programmer error.
  void _fail(Object error, StackTrace stackTrace) {
    if (error is Exception) {
      _controller.add(GraphQLTransportFailure(NetworkFailure(error)));
    } else {
      _controller.addError(error, stackTrace);
    }
    _stop();
    _finish();
  }

  void _finish() {
    _removeListener?.call();
    _removeListener = null;
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  static Stream<LinkResult> _unterminated(LinkRequest request) => Stream.error(
    StateError(
      'The last link forwarded ${request.document.name}: end the chain with '
      'a terminating link, such as MockLink or HttpLink.',
    ),
  );
}
