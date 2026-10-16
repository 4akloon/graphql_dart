import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'client_socket.dart';
import 'reconnect_policy.dart';

/// What a `WebSocketLink` was configured with, as its collaborators read it.
@internal
final class SocketSettings({
  /// Opens a socket.
  required final Future<ClientSocket> Function() connect,

  /// The payload of `connection_init`, asked for at each connection.
  required final FutureOr<JsonObject?> Function()? connectionParams,

  /// How long the server has to send `connection_ack`.
  required final Duration connectionAckTimeout,

  /// The interval of the client's pings; null for none.
  required final Duration? keepAlive,

  /// When a lost connection is tried again.
  required final ReconnectPolicy policy,
}) {
  /// Creates the settings.
  this;
}
