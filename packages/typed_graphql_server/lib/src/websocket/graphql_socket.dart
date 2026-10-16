/// One WebSocket connection, as the graphql-ws handler sees it; an adapter
/// (for example `typed_graphql_shelf`) implements it over its own WebSocket.
///
/// An adapter must:
///
/// - deliver text frames to [incoming] as they are, and binary frames
///   decoded as UTF-8 (the handler then fails them as JSON and closes
///   `4400`);
/// - complete [incoming] when the connection closes, whoever closed it;
/// - answer WebSocket ping frames and send them for keep-alive: the
///   handler never sends graphql-ws `ping` messages on its own.
///
/// {@category websocket}
abstract interface class GraphQLSocket {
  /// The subprotocol negotiated in the upgrade, null when the client offered
  /// none the host accepted; the handler requires
  /// `GraphQLWsHandler.protocol`.
  String? get protocol;

  /// The text frames the client sends, in order.
  Stream<String> get incoming;

  /// Sends [text] as one text frame, without waiting for the peer: it never
  /// throws, and a frame sent after the connection closed is dropped.
  void send(String text);

  /// Closes the connection with a WebSocket close [code] and [reason] (at
  /// most 123 UTF-8 bytes), completing when it is closed.
  Future<void> close(int code, String reason);
}
