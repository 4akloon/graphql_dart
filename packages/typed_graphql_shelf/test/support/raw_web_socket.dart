import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A WebSocket client on a raw [Socket], so that a test can send a frame
/// header on its own and read the server's frames byte by byte.
final class RawWebSocket {
  RawWebSocket._(this._socket) {
    _socket.listen(_onBytes, onDone: _closed.complete);
  }

  /// Connects to [port] on loopback and sends the upgrade request; read the
  /// answer with [statusLine] and [frames] after [until].
  static Future<RawWebSocket> open(
    int port, {
    String protocol = 'graphql-transport-ws',
  }) async {
    final client = RawWebSocket._(
      await Socket.connect(InternetAddress.loopbackIPv4, port),
    );
    client._socket.write(
      'GET /graphql HTTP/1.1\r\n'
      'host: 127.0.0.1:$port\r\n'
      'connection: Upgrade\r\n'
      'upgrade: websocket\r\n'
      'sec-websocket-version: 13\r\n'
      'sec-websocket-key: ${base64Encode(List.filled(16, 3))}\r\n'
      'sec-websocket-protocol: $protocol\r\n'
      '\r\n',
    );
    return client;
  }

  final Socket _socket;
  final List<int> _received = [];
  final Completer<void> _closed = Completer<void>();
  final List<Completer<void>> _waiters = [];

  /// The bytes the server sent after its response head.
  List<int> get frames {
    final end = _headEnd();
    return end < 0 ? const [] : _received.sublist(end);
  }

  /// The status line of the response, once it has arrived.
  String? get statusLine {
    final end = _headEnd();
    if (end < 0) return null;
    return ascii.decode(_received.sublist(0, end)).split('\r\n').first;
  }

  /// Completes when [test] holds for the frame bytes or the server closed.
  Future<void> until(bool Function(List<int> frames) test) async {
    while (!test(frames) && !_closed.isCompleted) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await Future.any([waiter.future, _closed.future]);
    }
  }

  /// Sends the header of a masked text frame that declares [length] payload
  /// bytes, and no payload.
  void sendTextHeader(int length) {
    final header = ByteData(14)
      ..setUint8(0, 0x81)
      ..setUint8(1, 0x80 | 127)
      ..setUint64(2, length);
    _socket.add(header.buffer.asUint8List());
  }

  /// Closes the connection without a closing handshake.
  void destroy() => _socket.destroy();

  int _headEnd() {
    for (var i = 3; i < _received.length; i++) {
      if (_received[i - 3] == 13 &&
          _received[i - 2] == 10 &&
          _received[i - 1] == 13 &&
          _received[i] == 10) {
        return i + 1;
      }
    }
    return -1;
  }

  void _onBytes(List<int> bytes) {
    _received.addAll(bytes);
    for (final waiter in _waiters.toList()) {
      waiter.complete();
    }
    _waiters.clear();
  }
}
