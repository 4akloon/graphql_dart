import 'dart:async';

import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// Two connected ends of an in-memory text socket: [client] for
/// `WebSocketLink`, [server] for `GraphQLWsHandler.serve`.
///
/// A frame sent on one end arrives on the other. Closing either end closes
/// both, once, and records the code and reason both ends report.
final class SocketPair {
  /// Creates a pair whose server end reports [protocol] as negotiated.
  SocketPair({this.protocol = GraphQLWsHandler.protocol});

  /// The sub-protocol the server end reports.
  final String? protocol;

  final StreamController<String> _toServer = StreamController<String>();
  final StreamController<String> _toClient = StreamController<String>();

  /// The close code, once closed.
  int? closeCode;

  /// The close reason, once closed.
  String? closeReason;

  /// Whether either end closed the socket.
  bool get isClosed => _toClient.isClosed;

  // `late` because the ends need `this`; nothing reads them before the
  // constructor returns.
  /// The client's end.
  late final ClientSocket client = _ClientEnd(this);

  /// The server's end.
  late final GraphQLSocket server = _ServerEnd(this);

  void _close(int? code, String? reason) {
    if (isClosed) return;
    closeCode = code;
    closeReason = reason;
    // Not awaited: a controller nobody listens to never reports done.
    unawaited(_toServer.close());
    unawaited(_toClient.close());
  }
}

final class _ClientEnd implements ClientSocket {
  _ClientEnd(this._pair);

  final SocketPair _pair;

  @override
  Stream<String> get messages => _pair._toClient.stream;

  @override
  void send(String text) {
    if (!_pair.isClosed) _pair._toServer.add(text);
  }

  @override
  Future<void> close([int? code, String? reason]) async =>
      _pair._close(code, reason);

  @override
  int? get closeCode => _pair.closeCode;

  @override
  String? get closeReason => _pair.closeReason;
}

final class _ServerEnd implements GraphQLSocket {
  _ServerEnd(this._pair);

  final SocketPair _pair;

  @override
  String? get protocol => _pair.protocol;

  @override
  Stream<String> get incoming => _pair._toServer.stream;

  @override
  void send(String text) {
    if (!_pair.isClosed) _pair._toClient.add(text);
  }

  @override
  Future<void> close(int code, String reason) async =>
      _pair._close(code, reason);
}
