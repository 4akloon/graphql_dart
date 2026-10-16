import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../server/graphql_server.dart';
import '../server/request_info.dart';
import '../server/server_request.dart';
import 'client_message.dart';
import 'socket_error_reporter.dart';
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
    this.reporter = const SocketErrorReporter(null),
  });

  /// The server that runs the operations.
  final GraphQLServer<C> server;

  /// The upgrade request the connection came on.
  final RequestInfo upgrade;

  /// How many operations may be in flight at once.
  final int maxOperations;

  /// Writes a message to the socket.
  final void Function(String text) send;

  /// Told about the errors the operations swallow.
  final SocketErrorReporter reporter;

  final Map<String, SocketOperation> _running = {};
  int _inFlight = 0;

  /// Whether an operation with [id] is running (not cancelled).
  bool contains(String id) => _running.containsKey(id);

  /// Whether [maxOperations] operations are in flight.
  ///
  /// A cancelled operation stays in flight until the server stops working on
  /// its request, so a client that subscribes and completes in a loop cannot
  /// start more than [maxOperations] executions.
  bool get isFull => _inFlight >= maxOperations;

  /// Registers and starts the operation of [message].
  ///
  /// Each message gets a `POST` with the upgrade's headers and a JSON
  /// content type, so the mutation guard and the CSRF rule see an ordinary
  /// request; the Origin check on the upgrade is what protects them
  /// (spec section 9).
  void start(SubscribeMessage message, JsonObject? connectionParams) {
    final signal = CancelSignal();
    final operation = SocketOperation(
      id: message.id,
      handle: server.handle,
      request: ServerRequest(
        params: message.request,
        info: upgrade.withConnection(
          connectionParams,
          method: 'POST',
          headers: const {'content-type': 'application/json'},
        ),
        cancelSignal: signal,
      ),
      signal: signal,
      send: send,
      onReleased: _release,
      reporter: reporter,
    );
    _running[message.id] = operation;
    _inFlight++;
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
  void _release(SocketOperation operation) {
    _inFlight--;
    if (identical(_running[operation.id], operation)) {
      _running.remove(operation.id);
    }
  }
}
