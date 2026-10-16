import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../server/graphql_server.dart';
import '../server/request_info.dart';
import '../server/server_request.dart';
import 'client_message.dart';
import 'socket_operation.dart';

/// The operations a graphql-ws connection is running, by id.
@internal
final class SocketOperations<C> {
  /// Creates an empty registry for the connection upgraded by [upgrade].
  SocketOperations({
    required this.server,
    required this.upgrade,
    required this.maxOperations,
    required this.send,
  });

  /// The server that runs the operations.
  final GraphQLServer<C> server;

  /// The upgrade request the connection came on.
  final RequestInfo upgrade;

  /// How many operations may run at once.
  final int maxOperations;

  /// Writes a message to the socket.
  final void Function(String text) send;

  final Map<String, SocketOperation<C>> _running = {};

  /// How many operations are running.
  int get length => _running.length;

  /// Whether an operation with [id] is running.
  bool contains(String id) => _running.containsKey(id);

  /// Whether [maxOperations] operations are running.
  bool get isFull => _running.length >= maxOperations;

  /// Registers and starts the operation of [message].
  ///
  /// Each message gets a `POST` with the upgrade's headers and a JSON
  /// content type, so the mutation guard and the CSRF rule see an ordinary
  /// request; the Origin check on the upgrade is what protects them
  /// (spec section 9).
  void start(SubscribeMessage message, JsonObject? connectionParams) {
    final signal = CancelSignal();
    final operation = SocketOperation<C>(
      id: message.id,
      server: server,
      request: ServerRequest(
        params: message.request,
        info: RequestInfo(
          method: 'POST',
          uri: upgrade.uri,
          headers: {...upgrade.headers, 'content-type': 'application/json'},
          source: upgrade.source,
          connectionParams: connectionParams,
        ),
        cancelSignal: signal,
      ),
      signal: signal,
      send: send,
      onEnded: _remove,
    );
    _running[message.id] = operation;
    unawaited(operation.run());
  }

  /// Cancels the operation [id] and frees the id; an unknown id is ignored.
  void cancel(String id) => _running.remove(id)?.cancel();

  /// Cancels every operation.
  void cancelAll() {
    final operations = _running.values.toList();
    _running.clear();
    for (final operation in operations) {
      operation.cancel();
    }
  }

  // The id may already belong to a newer operation after a `complete`.
  void _remove(SocketOperation<C> operation) {
    if (identical(_running[operation.id], operation)) {
      _running.remove(operation.id);
    }
  }
}
