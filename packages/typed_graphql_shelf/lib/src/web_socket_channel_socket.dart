import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A [GraphQLSocket] over the [WebSocketChannel] that `shelf_web_socket`
/// hands to a connection.
@internal
final class WebSocketChannelSocket implements GraphQLSocket {
  /// Wraps [_channel], whose negotiated subprotocol is [protocol].
  WebSocketChannelSocket(this._channel, this.protocol)
    : incoming = _channel.stream.map(_text);

  final WebSocketChannel _channel;
  bool _isClosed = false;

  @override
  final String? protocol;

  @override
  final Stream<String> incoming;

  // A binary frame is decoded with replacement characters so that it fails
  // as JSON and closes the socket with `4400`, instead of throwing here.
  static String _text(Object? frame) => switch (frame) {
    String() => frame,
    List<int>() => utf8.decode(frame, allowMalformed: true),
    _ => '$frame',
  };

  @override
  void send(String text) {
    if (_isClosed || _channel.closeCode != null) {
      return;
    }
    _channel.sink.add(text);
  }

  @override
  Future<void> close(int code, String reason) async {
    _isClosed = true;
    await _channel.sink.close(code, reason);
  }
}
