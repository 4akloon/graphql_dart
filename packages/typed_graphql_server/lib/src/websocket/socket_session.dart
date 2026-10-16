import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/graphql_server.dart';
import '../server/request_info.dart';
import 'client_message.dart';
import 'client_message_reader.dart';
import 'connection_decision.dart';
import 'connection_handshake.dart';
import 'graphql_socket.dart';
import 'graphql_ws_options.dart';
import 'server_messages.dart';
import 'ws_close.dart';

/// One graphql-ws connection: reads its frames, answers them and closes the
/// socket on a protocol violation (spec section 9).
@internal
final class SocketSession<C> {
  /// Creates the session of [socket], upgraded by [upgrade].
  SocketSession({
    required this.server,
    required this.options,
    required this.socket,
    required this.upgrade,
  }) : _handshake = ConnectionHandshake(options, upgrade),
       _reader = ClientMessageReader(options.maxJsonDepth);

  /// The server that runs the operations.
  final GraphQLServer<C> server;

  /// The options of the handler.
  final GraphQLWsOptions options;

  /// The connection.
  final GraphQLSocket socket;

  /// The upgrade request the connection came on.
  final RequestInfo upgrade;

  final ConnectionHandshake _handshake;
  final ClientMessageReader _reader;
  final ServerMessages _messages = const ServerMessages();
  final Completer<void> _ended = Completer<void>();
  bool _isClosed = false;

  /// Serves the connection; completes when `incoming` ends or fails.
  Future<void> run() {
    _handshake.startTimer(() => _close(WsClose.initTimeout));
    socket.incoming.listen(
      _onFrame,
      onError: (Object _) => _end(),
      onDone: _end,
      cancelOnError: true,
    );
    return _ended.future;
  }

  void _end() {
    _handshake.stopTimer();
    if (!_ended.isCompleted) {
      _ended.complete();
    }
  }

  void _onFrame(String text) {
    if (_isClosed) {
      return;
    }
    if (text.length > options.maxMessageLength) {
      _close(WsClose.messageTooBig);
      return;
    }
    final message = _reader.read(text);
    switch (message) {
      case null:
        _close(WsClose.invalidMessage);
      case InitMessage(:final payload):
        unawaited(_initialise(payload));
      case PingMessage(:final payload):
        _send(_messages.pong(payload));
      case PongMessage():
        break;
      case SubscribeMessage():
        _subscribe(message);
      case CompleteMessage():
        break;
    }
  }

  Future<void> _initialise(JsonObject? payload) async {
    if (_handshake.hasInit) {
      _close(WsClose.tooManyInits);
      return;
    }
    final ConnectionDecision decision;
    try {
      decision = await _handshake.decide(payload);
    } on Object {
      _close(WsClose.internalError);
      return;
    }
    if (_isClosed) {
      return;
    }
    switch (decision) {
      case AcceptConnection(:final payload):
        _handshake.acknowledge();
        _send(_messages.ack(payload));
      case RefuseConnection():
        _close(WsClose.forbidden);
    }
  }

  void _subscribe(SubscribeMessage message) {
    if (!_handshake.isAcknowledged) {
      _close(WsClose.unauthorized);
    }
  }

  void _send(String text) {
    if (!_isClosed) {
      socket.send(text);
    }
  }

  void _close(WsClose reason) {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _handshake.stopTimer();
    try {
      socket
          .close(reason.code, reason.reason)
          .then<void>(
            (_) {},
            onError: (Object _) {},
          );
    } on Object {
      // A socket that fails to close is gone already; nothing is left to do.
    }
  }
}
