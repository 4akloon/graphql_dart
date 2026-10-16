import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../execution/masked_message.dart';
import '../server/server_request.dart';
import '../server/server_response.dart';
import 'server_messages.dart';
import 'socket_error_reporter.dart';

/// One `subscribe` of a graphql-ws connection: runs the request through the
/// server and writes its `next`, `error` and `complete` messages.
@internal
final class SocketOperation {
  /// Creates the operation [id]. [handle] is the server's `handle`, [send]
  /// writes a message to the socket and [onReleased] tells the registry that
  /// the operation holds nothing any more.
  SocketOperation({
    required this.id,
    required this.handle,
    required this.request,
    required this.signal,
    required this.send,
    required this.onReleased,
    this.reporter = const SocketErrorReporter(null),
  });

  /// The id the client chose.
  final String id;

  /// Runs [request] through the server.
  final Future<ServerResponse> Function(ServerRequest request) handle;

  /// The request, carrying [signal].
  final ServerRequest request;

  /// Cancelled when the client completes the operation or disconnects.
  final CancelSignal signal;

  /// Writes a message to the socket.
  final void Function(String text) send;

  /// Called once when the operation holds nothing any more: it ended, or it
  /// was cancelled and the server stopped working on it. A cancelled
  /// operation whose request is still running is not released yet, so the
  /// registry counts it against `maxOperations`.
  final void Function(SocketOperation operation) onReleased;

  /// Told about the errors the operation swallows.
  final SocketErrorReporter reporter;

  final ServerMessages _messages = const ServerMessages();
  StreamSubscription<ExecutionResult>? _subscription;
  bool _isCancelled = false;
  bool _isHandling = true;
  bool _isReleased = false;

  /// Runs the request and sends what it produces.
  Future<void> run() async {
    final ServerResponse response;
    try {
      response = await handle(request);
    } on Object catch (error, stackTrace) {
      // A boundary: the server answers its own failures, so this is a bug
      // there; it is reported (an Error too, never rethrown into the zone)
      // and the client gets the masked message.
      _isHandling = false;
      reporter.report(error, stackTrace);
      _sendUnexpected();
      return;
    }
    _isHandling = false;
    if (_isCancelled) {
      _discard(response);
      _release();
      return;
    }
    switch (response) {
      case SingleResponse(:final payload):
        _sendSingle(payload);
      case StreamResponse(:final results):
        _forward(results);
    }
  }

  /// Stops the operation and sends nothing more for it.
  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _subscription?.cancel().ignore();
    signal.cancel();
    if (!_isHandling) {
      _release();
    }
  }

  // A stream that arrives after `complete` was never wanted: listening and
  // cancelling lets its source release what it holds.
  void _discard(ServerResponse response) {
    if (response case StreamResponse(:final results)) {
      results.listen(null).cancel().ignore();
    }
  }

  void _sendSingle(ResponsePayload payload) {
    switch (payload) {
      case ExecutionResult():
        send(_messages.next(id, payload));
        send(_messages.complete(id));
      case RequestErrorResult(:final errors):
        send(_messages.error(id, errors));
    }
    _release();
  }

  void _forward(Stream<ExecutionResult> results) {
    _subscription = results.listen(
      (result) => send(_messages.next(id, result)),
      onError: (Object error, StackTrace stackTrace) {
        reporter.report(error, stackTrace);
        _sendUnexpected();
      },
      onDone: () {
        send(_messages.complete(id));
        _release();
      },
      cancelOnError: true,
    );
  }

  void _sendUnexpected() {
    if (!_isCancelled) {
      send(
        _messages.error(id, [
          GraphQLError(
            const MaskedMessage().text,
            extensions: JsonObject({
              'code': JsonString(DiagnosticCode.unexpectedError.id),
            }),
          ),
        ]),
      );
    }
    _release();
  }

  void _release() {
    if (!_isReleased) {
      _isReleased = true;
      onReleased(this);
    }
  }
}
