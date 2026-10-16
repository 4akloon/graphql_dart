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

  late final StreamController<GraphQLResponse<D>> _controller =
      StreamController(
        onListen: _start,
        onCancel: _stop,
        onPause: () => _subscription?.pause(),
        onResume: () => _subscription?.resume(),
      );
  StreamSubscription<LinkResult>? _subscription;
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
    _subscription = _link
        .request(_request, _unterminated)
        .listen(
          (result) => _controller.add(_decoder.decode(result)),
          onError: _fail,
          onDone: _finish,
        );
  }

  Future<void>? _stop() {
    _removeListener?.call();
    _removeListener = null;
    return _subscription?.cancel();
  }

  void _cancel(CancelToken token) {
    unawaited(_stop());
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
    unawaited(_stop());
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
      'a terminating link, such as HttpLink.',
    ),
  );
}
