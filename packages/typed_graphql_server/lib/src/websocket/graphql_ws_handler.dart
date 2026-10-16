import 'package:typed_graphql/typed_graphql.dart';

import '../server/graphql_server.dart';
import '../server/request_info.dart';
import 'graphql_socket.dart';
import 'graphql_ws_options.dart';
import 'origin_policy.dart';
import 'socket_session.dart';
import 'ws_close.dart';

/// Serves the `graphql-transport-ws` protocol of the graphql-ws library over
/// a [GraphQLSocket], running each operation through a [GraphQLServer].
///
/// The handler knows nothing of HTTP: a host accepts the upgrade, wraps the
/// connection in a [GraphQLSocket] and calls [serve].
///
/// {@category websocket}
final class GraphQLWsHandler<C> {
  /// Creates a handler for [server].
  ///
  /// Throws an [ArgumentError] when a duration or a limit in [options] is
  /// not positive or `maxJsonDepth` is outside `1` to
  /// [JsonReader.maxSupportedDepth].
  GraphQLWsHandler(
    this.server, {
    this.options = const GraphQLWsOptions(),
  }) : _origins = OriginPolicy(options.allowedOrigins) {
    _check(options);
  }

  /// The WebSocket subprotocol this handler speaks.
  static const String protocol = 'graphql-transport-ws';

  /// The server that runs the operations.
  final GraphQLServer<C> server;

  /// The limits and hooks of this handler.
  final GraphQLWsOptions options;

  final OriginPolicy _origins;
  int _openSessions = 0;

  /// Whether [upgrade] may become a connection, judged by its `Origin`.
  ///
  /// A host calls this before upgrading and answers `403` when it is false;
  /// [serve] checks again (defence in depth). An upgrade with no `Origin`
  /// is not from a browser and passes; so does one whose `Origin` has the
  /// host of its `Host` header or is in `allowedOrigins`.
  bool allowsUpgrade(RequestInfo upgrade) => _origins.allows(upgrade);

  /// Serves [socket], upgraded by [upgrade], until it closes.
  ///
  /// Never throws: a refusal or a failure closes the socket with a code.
  Future<void> serve(GraphQLSocket socket, RequestInfo upgrade) async {
    try {
      final refusal = _refusal(socket, upgrade);
      if (refusal != null) {
        await socket.close(refusal.code, refusal.reason);
        return;
      }
      _openSessions++;
      try {
        await SocketSession<C>(
          server: server,
          options: options,
          socket: socket,
          upgrade: upgrade,
        ).run();
      } finally {
        _openSessions--;
      }
    } on Object {
      await _closeAfterFailure(socket);
    }
  }

  WsClose? _refusal(GraphQLSocket socket, RequestInfo upgrade) {
    if (_openSessions >= options.maxConnections) {
      return WsClose.tryAgainLater;
    }
    if (socket.protocol != protocol) {
      return WsClose.subprotocolNotAcceptable;
    }
    return allowsUpgrade(upgrade) ? null : WsClose.forbidden;
  }

  Future<void> _closeAfterFailure(GraphQLSocket socket) async {
    try {
      await socket.close(
        WsClose.internalError.code,
        WsClose.internalError.reason,
      );
    } on Object {
      // The socket is gone; nothing is left to tell the client.
    }
  }

  static void _check(GraphQLWsOptions options) {
    _positive(
      'connectionInitTimeout',
      options.connectionInitTimeout,
      options.connectionInitTimeout > .zero,
    );
    _positive(
      'maxOperations',
      options.maxOperations,
      options.maxOperations > 0,
    );
    _positive(
      'maxMessageLength',
      options.maxMessageLength,
      options.maxMessageLength > 0,
    );
    _positive(
      'maxConnections',
      options.maxConnections,
      options.maxConnections > 0,
    );
    if (options.maxJsonDepth < 1 ||
        options.maxJsonDepth > JsonReader.maxSupportedDepth) {
      throw ArgumentError.value(
        options.maxJsonDepth,
        'maxJsonDepth',
        'must be between 1 and JsonReader.maxSupportedDepth',
      );
    }
  }

  static void _positive(String name, Object value, bool isPositive) {
    if (!isPositive) {
      throw ArgumentError.value(value, name, 'must be positive');
    }
  }
}
