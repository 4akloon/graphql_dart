import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_result.dart';
import 'client_socket.dart';
import 'open_operation.dart';
import 'socket_end.dart';
import 'socket_message.dart';
import 'socket_message_codec.dart';
import 'socket_operations.dart';
import 'socket_settings.dart';

/// One socket's life: the handshake, the ack timer, the keep-alive, and the
/// reading of every frame into [SocketOperations].
///
/// [run] completes once, with how the socket ended; it never throws.
@internal
final class SocketConnection {
  /// Creates the connection over [_socket].
  SocketConnection(this._socket, this._settings, this._operations);

  final ClientSocket _socket;
  final SocketSettings _settings;
  final SocketOperations _operations;
  final Completer<SocketEnd> _ended = Completer();
  final SocketMessageCodec _codec = const SocketMessageCodec();
  StreamSubscription<String>? _subscription;
  Timer? _ackTimer;
  Timer? _keepAliveTimer;
  bool _isAwaitingPong = false;
  bool _isAcknowledged = false;
  bool _hasReceivedResult = false;

  /// Whether the server sent `connection_ack`.
  bool get isAcknowledged => _isAcknowledged;

  /// Whether a `next` arrived: the proof that the connection was useful, so
  /// that a server which acknowledges and then drops the socket does not
  /// reset the reconnection count.
  bool get hasReceivedResult => _hasReceivedResult;

  /// Starts reading and sends `connection_init`; completes when the socket
  /// ends.
  Future<SocketEnd> run() {
    _subscription = _socket.messages.listen(
      _handleText,
      onError: (Object error) => _terminate(ConnectionLost(cause: error)),
      onDone: () => _end(
        ConnectionLost(
          closeCode: _socket.closeCode,
          closeReason: _socket.closeReason,
        ),
      ),
    );
    _ackTimer = Timer(_settings.connectionAckTimeout, _timeOutAck);
    unawaited(_sendInit());
    return _ended.future;
  }

  /// Tells the server to run [operation], once the connection is
  /// acknowledged; before that, the acknowledgement does it.
  void subscribe(OpenOperation operation) {
    if (!isAcknowledged || operation.isSent || _ended.isCompleted) {
      return;
    }
    operation.isSent = true;
    _send(SubscribeMessage(operation.id, operation.request.body));
  }

  /// Tells the server the caller no longer wants the operation [id].
  void complete(String id) {
    if (isAcknowledged && !_ended.isCompleted) {
      _send(CompleteMessage(id));
    }
  }

  /// Ends the connection for the link's own reasons and closes the socket.
  Future<void> close(int code, String reason) {
    _end(ConnectionLost(closeCode: code, closeReason: reason));
    return _closeSocket(code, reason);
  }

  Future<void> _sendInit() async {
    try {
      final params = await _settings.connectionParams?.call();
      if (!_ended.isCompleted) {
        _send(ConnectionInitMessage(params));
      }
    } on Exception catch (error) {
      _end(ConnectionLost(closeCode: 4005, cause: error));
      await _closeSocket(4005, 'Internal client error');
    }
  }

  void _handleText(String text) {
    switch (_codec.decode(text)) {
      case DecodeSuccess(:final value):
        _handle(value);
      case final DecodeFailure failure:
        _reject('$failure');
    }
  }

  void _handle(SocketMessage message) {
    switch (message) {
      case ConnectionAckMessage():
        _acknowledge();
      case PingMessage():
        _send(const PongMessage());
      case PongMessage():
        _isAwaitingPong = false;
      case _ when !isAcknowledged:
        _reject('"${message.type}" came before "connection_ack"');
      case NextMessage(:final id, :final result):
        _hasReceivedResult = true;
        _operations.emit(id, LinkPayload(result));
      case ErrorMessage(:final id, :final errors):
        _operations.finish(
          id,
          last: LinkPayload(RequestErrorResult(errors: errors)),
        );
      case CompleteMessage(:final id):
        _operations.finish(id);
      case ConnectionInitMessage() || SubscribeMessage():
        _reject('a server cannot send "${message.type}"');
    }
  }

  void _acknowledge() {
    if (_isAcknowledged) {
      _reject('a second "connection_ack"');
      return;
    }
    _isAcknowledged = true;
    _ackTimer?.cancel();
    final interval = _settings.keepAlive;
    if (interval != null) {
      _keepAliveTimer = Timer.periodic(interval, (_) => _ping());
    }
    _operations.all.forEach(subscribe);
  }

  /// A ping every interval; a pong must come back before the next one, or
  /// the socket is dead (it may have frozen without closing).
  void _ping() {
    if (_isAwaitingPong) {
      _terminate(
        const ConnectionLost(closeCode: 4499, closeReason: 'Terminated'),
      );
      return;
    }
    _isAwaitingPong = true;
    _send(const PingMessage());
  }

  /// Ends the connection for a reason the socket did not report by closing,
  /// and closes the socket with 4499, so that a reconnection never leaves two
  /// live sockets. A client cannot send 1006, so 4499 is the code of the
  /// reference client's own "Terminated".
  void _terminate(SocketEnd end) {
    _end(end);
    unawaited(_closeSocket(4499, 'Terminated'));
  }

  void _timeOutAck() {
    _end(const AckTimedOut());
    unawaited(_closeSocket(4504, 'Connection acknowledgement timeout'));
  }

  /// 4400, "Bad request": the code graphql-ws gives for an invalid message.
  void _reject(String reason) {
    _end(MalformedMessage(reason));
    unawaited(_closeSocket(4400, 'Invalid message'));
  }

  void _end(SocketEnd end) {
    if (_ended.isCompleted) {
      return;
    }
    _ackTimer?.cancel();
    _keepAliveTimer?.cancel();
    unawaited(_subscription?.cancel());
    _ended.complete(end);
  }

  void _send(SocketMessage message) {
    // `Future.sync` turns anything `send` throws, an `Error` from a closed
    // sink included, into a future error, which `ignore` drops; the rules
    // forbid catching `Error`. The socket is closing, and its messages stream
    // reports the loss.
    Future<void>.sync(() => _socket.send(message.encode())).ignore();
  }

  Future<void> _closeSocket(int code, String reason) async {
    // As in `_send`: the socket may already be gone, and an `Error` from
    // its `close` must not escape either.
    await Future.sync(() => _socket.close(code, reason)).then<void>(
      (_) {},
      onError: (Object _) {},
    );
  }
}
