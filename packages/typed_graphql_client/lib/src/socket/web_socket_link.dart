import 'dart:async';
import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

import '../client/client_failure.dart';
import '../link/backoff.dart';
import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import '../upload/upload_files.dart';
import 'client_socket.dart';
import 'open_operation.dart';
import 'reconnect_policy.dart';
import 'socket_driver.dart';
import 'socket_operations.dart';
import 'socket_settings.dart';

/// A terminating link that sends operations over one WebSocket speaking
/// graphql-transport-ws (R8.4); it is the link for subscriptions, and
/// carries queries and mutations as well.
///
/// **Connecting.** The link is lazy: the first request calls [connect],
/// which must open a socket with the sub-protocol `graphql-transport-ws`
/// and wrap it in a [ClientSocket] (a `Future<ClientSocket> Function()`
/// rather than a type of its own: the app has nothing else to implement).
/// One socket carries every operation. The link sends `connection_init`,
/// with the object [connectionParams] returns, waits up to
/// [connectionAckTimeout] for `connection_ack`, and then sends each
/// operation as a `subscribe` with an id (`"1"`, `"2"`, ...) unique for the
/// link's life. The socket stays open after the last operation ends, until
/// [dispose].
///
/// **Results.** `next` is a [LinkPayload]; `error` is a [LinkPayload] of a
/// `RequestErrorResult` and ends the operation; `complete` ends it. A
/// caller that cancels its subscription sends `complete` for the id.
/// Messages for an unknown id are ignored. A message that breaks the
/// protocol closes the socket with 4400 and fails every operation with
/// `SocketFailure` `GQL470`; no acknowledgement in time closes it with 4504
/// and fails them with `GQL472`, without reconnecting (a 4504 close that a
/// *server* sends is retried like any other).
///
/// **Keeping alive.** A server `ping` is answered with `pong`. With
/// [keepAlive], the link also pings at that interval; if no `pong` came
/// back by the next one, it closes the socket with 4499 and reconnects.
///
/// **Reconnecting.** When the socket closes or [connect] throws while
/// operations are open, the link tries again after
/// `backoff.delayFor(n, random)`, up to [retryAttempts] failed attempts in a
/// row (an acknowledged connection gives the count back). A new socket gets
/// a new handshake, and every open query and subscription is subscribed
/// again under the same id; a mutation already sent is not (the server may
/// have run it) and ends with `NetworkFailure`. Codes the reference
/// client never retries (see the WebSocket guide), or running out of
/// attempts, end every operation with `SocketFailure` `GQL471` that holds
/// the close code, or with the `NetworkFailure` of the last [connect].
///
/// A request with `UploadFiles` in its context gets `UnsupportedOperation`
/// `GQL468`; one made after [dispose] gets `RequestCancelled` `GQL466`, as
/// the operations that were open.
///
/// {@category socket}
final class WebSocketLink extends Link {
  /// Creates a link that opens its socket with [connect].
  ///
  /// [connectionParams] gives the payload of `connection_init` at each
  /// connection (a token that may have been refreshed); [keepAlive] turns
  /// the client's pings on; [retryAttempts] failed attempts in a row are
  /// tried again, with [backoff] between them; [random] is the source of
  /// the backoff's jitter. A [connectionAckTimeout] or [keepAlive] that is not
  /// longer than zero, or a negative [retryAttempts], is an [ArgumentError].
  WebSocketLink({
    required Future<ClientSocket> Function() connect,
    FutureOr<JsonObject?> Function()? connectionParams,
    Duration connectionAckTimeout = const Duration(seconds: 10),
    Duration? keepAlive,
    int retryAttempts = 5,
    Backoff backoff = const Backoff(initialDelay: Duration(seconds: 1)),
    Random? random,
  }) {
    _requireLongerThanZero(connectionAckTimeout, 'connectionAckTimeout');
    if (keepAlive != null) {
      _requireLongerThanZero(keepAlive, 'keepAlive');
    }
    if (retryAttempts < 0) {
      throw ArgumentError.value(retryAttempts, 'retryAttempts', 'is negative');
    }
    _driver = SocketDriver(
      SocketSettings(
        connect: connect,
        connectionParams: connectionParams,
        connectionAckTimeout: connectionAckTimeout,
        keepAlive: keepAlive,
        policy: ReconnectPolicy(
          retryAttempts: retryAttempts,
          backoff: backoff,
          random: random ?? Random(),
        ),
      ),
      _operations,
    );
  }

  static void _requireLongerThanZero(Duration value, String name) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, name, 'must be longer than zero');
    }
  }

  final SocketOperations _operations = SocketOperations();
  // `late`: the driver needs the settings, which the constructor body builds.
  late final SocketDriver _driver;
  bool _isDisposed = false;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    if (request.context.entry<UploadFiles>() != null) {
      return Stream.value(
        const LinkFailure(
          UnsupportedOperation(
            .operationNotSupportedByLink,
            'WebSocketLink cannot send files; send them over HttpLink.',
          ),
        ),
      );
    }
    if (_isDisposed) {
      return Stream.value(_disposedFailure);
    }
    return OpenOperation(
      _operations.nextId(),
      request,
      onListen: _start,
      onCancel: _stop,
    ).controller.stream;
  }

  /// Closes the socket with 1000, ends every open operation with
  /// `RequestCancelled`, and refuses later requests.
  Future<void> dispose() async {
    _isDisposed = true;
    _operations.failAll(
      const RequestCancelled('The WebSocketLink was disposed.'),
    );
    await _driver.stop();
  }

  static const LinkResult _disposedFailure = LinkFailure(
    RequestCancelled('The WebSocketLink was disposed.'),
  );

  void _start(OpenOperation operation) {
    if (_isDisposed) {
      operation.end(_disposedFailure);
      return;
    }
    _operations.add(operation);
    _driver
      ..ensureRunning()
      ..subscribe(operation);
  }

  void _stop(OpenOperation operation) {
    if (_operations.remove(operation.id) && operation.isSent) {
      _driver.complete(operation.id);
    }
  }
}
