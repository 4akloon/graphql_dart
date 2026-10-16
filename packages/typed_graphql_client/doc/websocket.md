# WebSocket

Subscriptions travel over a WebSocket speaking the graphql-transport-ws
protocol. The package imports no socket library: the app opens the socket
and gives the link a `ClientSocket`, a small interface of text frames.

## The socket

A `ClientSocket` has the frames the server sends (`messages`, which ends
when the socket closes), `send`, `close`, and the `closeCode` and
`closeReason` once the stream has ended. Open the socket with the
sub-protocol `graphql-transport-ws`, and wrap it:

```text
final class ChannelSocket implements ClientSocket {
  ChannelSocket(this._channel);
  final WebSocketChannel _channel;

  Stream<String> get messages =>
      _channel.stream.where((frame) => frame is String).cast<String>();
  void send(String text) => _channel.sink.add(text);
  Future<void> close([int? code, String? reason]) =>
      _channel.sink.close(code, reason);
  int? get closeCode => _channel.closeCode;
  String? get closeReason => _channel.closeReason;
}
```
