/// The text-frame socket `WebSocketLink` talks graphql-transport-ws over.
///
/// The package imports no socket library: the app opens the socket, with
/// the sub-protocol `graphql-transport-ws`, and wraps it in this interface.
/// The link calls [send] and [close] and reads [messages]; it never opens a
/// socket itself, so it runs wherever the app's socket does.
///
/// An adapter over a `WebSocketChannel` or a browser `WebSocket` is a few
/// lines:
///
/// ```text
/// final class ChannelSocket implements ClientSocket {
///   ChannelSocket(this._channel);
///   final WebSocketChannel _channel;
///
///   Stream<String> get messages =>
///       _channel.stream.where((frame) => frame is String).cast<String>();
///   void send(String text) => _channel.sink.add(text);
///   Future<void> close([int? code, String? reason]) =>
///       _channel.sink.close(code, reason);
///   int? get closeCode => _channel.closeCode;
///   String? get closeReason => _channel.closeReason;
/// }
/// ```
///
/// A browser `WebSocket` adapter forwards `onMessage` text frames to a
/// stream controller, closes the controller in `onClose` after saving
/// `event.code` and `event.reason`, and calls `socket.close(code, reason)`.
///
/// {@category socket}
abstract interface class ClientSocket {
  /// The text frames the server sends, in order. The stream ends when the
  /// socket closes, whoever closed it; an error event is a network loss
  /// and may be sent as an error or as the end of the stream.
  Stream<String> get messages;

  /// Sends one text frame. The link only calls it on an open socket; a
  /// socket that is already closing may ignore the call or throw, an
  /// [Exception] or an [Error] such as a [StateError] from a closed sink: the
  /// link drops the failure and waits for [messages] to report the loss.
  void send(String text);

  /// Closes the socket with [code] and [reason], and completes once it is
  /// closed.
  Future<void> close([int? code, String? reason]);

  /// The close code the closing handshake carried, known once [messages]
  /// has ended; null when there was none.
  int? get closeCode;

  /// The close reason that came with [closeCode].
  String? get closeReason;
}
