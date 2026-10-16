import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../execution/masked_message.dart';
import '../server/graphql_server.dart';
import '../server/server_request.dart';
import '../server/server_response.dart';
import 'server_messages.dart';

/// One `subscribe` of a graphql-ws connection: runs the request through the
/// server and writes its `next`, `error` and `complete` messages.
@internal
final class SocketOperation<C> {
  /// Creates the operation [id]; [send] writes a message to the socket and
  /// [onEnded] tells the registry the operation finished by itself.
  SocketOperation({
    required this.id,
    required this.server,
    required this.request,
    required this.signal,
    required this.send,
    required this.onEnded,
  });

  /// The id the client chose.
  final String id;

  /// The server that runs the request.
  final GraphQLServer<C> server;

  /// The request, carrying [signal].
  final ServerRequest request;

  /// Cancelled when the client completes the operation or disconnects.
  final CancelSignal signal;

  /// Writes a message to the socket.
  final void Function(String text) send;

  /// Called once when the operation ends without being cancelled.
  final void Function(SocketOperation<C> operation) onEnded;

  final ServerMessages _messages = const ServerMessages();
  StreamSubscription<ExecutionResult>? _subscription;
  bool _isCancelled = false;

  /// Runs the request and sends what it produces.
  Future<void> run() async {
    final ServerResponse response;
    try {
      response = await server.handle(request);
    } on Object {
      // The server reports its own failures as responses; this guards the
      // socket against a bug there without leaking its text.
      _sendUnexpected();
      return;
    }
    if (_isCancelled) {
      _discard(response);
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
    onEnded(this);
  }

  void _forward(Stream<ExecutionResult> results) {
    _subscription = results.listen(
      (result) => send(_messages.next(id, result)),
      onError: (Object _) => _sendUnexpected(),
      onDone: () {
        send(_messages.complete(id));
        onEnded(this);
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
    onEnded(this);
  }
}
