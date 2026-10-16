import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// An in-memory [GraphQLSocket] that records what the server sends.
final class FakeSocket implements GraphQLSocket {
  /// A socket that closes at once. With [endsIncomingOnClose] false, `close`
  /// leaves `incoming` open, as a peer that never finishes the closing
  /// handshake does; [closeGate], when given, is awaited before `close`
  /// completes.
  FakeSocket({
    this.protocol = 'graphql-transport-ws',
    this.endsIncomingOnClose = true,
    this.closeGate,
  });

  /// Whether `close` ends `incoming`.
  final bool endsIncomingOnClose;

  /// Awaited by `close` before it completes; null completes at once.
  final Future<void>? closeGate;

  @override
  final String? protocol;

  final StreamController<String> _incoming = StreamController<String>();
  final Completer<void> _closed = Completer<void>();
  final List<Map<String, Object?>> _sent = [];
  final List<Completer<Map<String, Object?>>> _waiting = [];
  int _read = 0;

  /// The decoded messages the server sent, in order.
  List<Map<String, Object?>> get sent => List.unmodifiable(_sent);

  /// The code of the first close the server asked for; null while open.
  int? closeCode;

  /// The reason of the first close the server asked for; null while open.
  String? closeReason;

  /// How many times the server asked to close.
  int closeCalls = 0;

  /// Completes when the server closes the socket.
  Future<void> get closed => _closed.future;

  @override
  Stream<String> get incoming => _incoming.stream;

  /// Delivers a text frame to the server.
  void receive(String text) => _incoming.add(text);

  /// Ends the incoming frames, as a dropped connection does.
  Future<void> disconnect() => _incoming.close();

  /// The next message the server sends that the test has not read yet.
  Future<Map<String, Object?>> nextSent() {
    if (_read < _sent.length) {
      return Future.value(_sent[_read++]);
    }
    final waiting = Completer<Map<String, Object?>>();
    _waiting.add(waiting);
    return waiting.future;
  }

  @override
  void send(String text) {
    final message = jsonDecode(text) as Map<String, Object?>;
    _sent.add(message);
    if (_waiting.isNotEmpty) {
      _read++;
      _waiting.removeAt(0).complete(message);
    }
  }

  @override
  Future<void> close(int code, String reason) async {
    closeCalls++;
    closeCode ??= code;
    closeReason ??= reason;
    if (!_closed.isCompleted) {
      _closed.complete();
    }
    if (endsIncomingOnClose) {
      // Not awaited: with no listener the controller's close never completes.
      unawaited(_incoming.close());
    }
    await closeGate;
  }
}
