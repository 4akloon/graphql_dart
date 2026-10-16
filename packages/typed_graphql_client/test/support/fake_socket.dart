import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql_client/typed_graphql_client.dart';

/// A [ClientSocket] the test drives: it records what the client sends and
/// closes, and the test plays the server.
final class FakeSocket implements ClientSocket {
  final StreamController<String> _incoming = StreamController();
  int? _closeCode;
  String? _closeReason;

  /// The texts the client sent, in order.
  final List<String> sent = [];

  /// The close code the client gave, or null while it has not closed.
  int? clientCloseCode;

  /// The close reason the client gave.
  String? clientCloseReason;

  /// Whether the client called [close].
  bool isClosedByClient = false;

  /// What the client sent, as the `type` of each message.
  List<String> get sentTypes => [
    for (final message in sentMessages) '${message['type']}',
  ];

  /// What the client sent, decoded.
  List<Map<String, Object?>> get sentMessages => [
    for (final text in sent) jsonDecode(text) as Map<String, Object?>,
  ];

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close([int? code, String? reason]) {
    isClosedByClient = true;
    clientCloseCode = code;
    clientCloseReason = reason;
    return _end(code, reason);
  }

  /// The server sends [text].
  void serverSends(String text) => _incoming.add(text);

  /// The server sends [message] as JSON.
  void serverSendsJson(Map<String, Object?> message) =>
      serverSends(jsonEncode(message));

  /// The server answers the handshake.
  void serverAcknowledges() =>
      serverSendsJson(const {'type': 'connection_ack'});

  /// The server closes the socket with [code] and [reason].
  Future<void> serverCloses(int code, String reason) => _end(code, reason);

  /// The network drops: the stream ends with no close code, as on a
  /// browser's code 1006.
  Future<void> serverDrops() => _end(1006, '');

  Future<void> _end(int? code, String? reason) {
    if (_incoming.isClosed) {
      return Future.value();
    }
    _closeCode = code;
    _closeReason = reason;
    return _incoming.close();
  }
}

/// The `connect` callback of a link under test: it hands out [FakeSocket]s
/// in order and counts the connections.
final class FakeSocketServer {
  final List<Exception> _failures = [];

  /// The sockets handed out, in order.
  final List<FakeSocket> sockets = [];

  /// How many times the link called [connect], failed ones included.
  int connectionCount = 0;

  /// The socket of the latest connection.
  FakeSocket get latest => sockets.last;

  /// Makes the next call to [connect] throw [failure].
  void failNext(Exception failure) => _failures.add(failure);

  /// The callback to give a link.
  Future<ClientSocket> connect() async {
    connectionCount++;
    if (_failures.isNotEmpty) {
      throw _failures.removeAt(0);
    }
    final socket = FakeSocket();
    sockets.add(socket);
    return socket;
  }
}
