import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// A graphql-ws message a client may send: the five types a server accepts.
///
/// Messages compare by value so that tests can state what was read.
@internal
sealed class ClientMessage {
  const ClientMessage();
}

/// `connection_init`: the first message, with the connection parameters.
@internal
final class InitMessage extends ClientMessage {
  /// Creates the message with its optional [payload].
  const InitMessage(this.payload);

  /// The connection parameters, null when the client sent none.
  final JsonObject? payload;

  @override
  bool operator ==(Object other) =>
      other is InitMessage && other.payload == payload;

  @override
  int get hashCode => Object.hash(InitMessage, payload);
}

/// `ping`: asks the server to answer with a `pong`.
@internal
final class PingMessage extends ClientMessage {
  /// Creates the message with its optional [payload].
  const PingMessage(this.payload);

  /// The payload the `pong` echoes, null when the client sent none.
  final JsonObject? payload;

  @override
  bool operator ==(Object other) =>
      other is PingMessage && other.payload == payload;

  @override
  int get hashCode => Object.hash(PingMessage, payload);
}

/// `pong`: the client's answer to a server `ping`; the server ignores it.
@internal
final class PongMessage extends ClientMessage {
  /// Creates the message with its optional [payload].
  const PongMessage(this.payload);

  /// The payload, null when the client sent none.
  final JsonObject? payload;

  @override
  bool operator ==(Object other) =>
      other is PongMessage && other.payload == payload;

  @override
  int get hashCode => Object.hash(PongMessage, payload);
}

/// `subscribe`: starts the operation [id] on the connection.
@internal
final class SubscribeMessage extends ClientMessage {
  /// Creates the message for operation [id] running [request].
  const SubscribeMessage(this.id, this.request);

  /// The id the client chose; every message about the operation carries it.
  final String id;

  /// The GraphQL request, whose `query` may be absent (persisted documents).
  final GraphQLRequest request;

  @override
  bool operator ==(Object other) =>
      other is SubscribeMessage && other.id == id && other.request == request;

  @override
  int get hashCode => Object.hash(SubscribeMessage, id, request);
}

/// `complete` from the client: stops the operation [id].
@internal
final class CompleteMessage extends ClientMessage {
  /// Creates the message for operation [id].
  const CompleteMessage(this.id);

  /// The id of the operation to stop.
  final String id;

  @override
  bool operator ==(Object other) => other is CompleteMessage && other.id == id;

  @override
  int get hashCode => Object.hash(CompleteMessage, id);
}
