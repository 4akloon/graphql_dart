import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// One message of the graphql-transport-ws protocol, as the link writes it
/// and (for the kinds a server sends) reads it.
@internal
sealed class SocketMessage {
  /// Creates a message.
  const SocketMessage();

  /// The `type` member.
  String get type;

  /// The members after `type`.
  Map<String, JsonValue> get members => const {};

  /// The message as JSON text, `type` first.
  String encode() =>
      JsonObject({'type': JsonString(type), ...members}).toString();
}

/// `connection_init`: the first message a client sends.
@internal
final class const ConnectionInitMessage([
  /// The connection parameters, such as a token.
  final JsonObject? payload,
]) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'connection_init';

  @override
  Map<String, JsonValue> get members => {'payload': ?payload};
}

/// `connection_ack`: the server accepts the connection.
@internal
final class const ConnectionAckMessage([
  /// What the server sent along, if anything.
  final JsonObject? payload,
]) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'connection_ack';

  @override
  Map<String, JsonValue> get members => {'payload': ?payload};
}

/// `ping`: either side asks the other to answer with a pong.
@internal
final class const PingMessage([
  /// What was sent along, if anything.
  final JsonObject? payload,
]) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'ping';

  @override
  Map<String, JsonValue> get members => {'payload': ?payload};
}

/// `pong`: the answer to a ping.
@internal
final class const PongMessage([
  /// What was sent along, if anything.
  final JsonObject? payload,
]) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'pong';

  @override
  Map<String, JsonValue> get members => {'payload': ?payload};
}

/// `subscribe`: a client starts an operation.
@internal
final class const SubscribeMessage(
  /// The operation's id on this socket.
  final String id,

  /// The request: query, variables, operation name, extensions.
  final GraphQLRequest request,
) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'subscribe';

  @override
  Map<String, JsonValue> get members => {
    'id': JsonString(id),
    'payload': request.toJson(),
  };
}

/// `next`: a server sends one execution result of an operation.
@internal
final class const NextMessage(
  /// The operation's id.
  final String id,

  /// The result.
  final ExecutionResult result,
) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'next';

  @override
  Map<String, JsonValue> get members => {
    'id': JsonString(id),
    'payload': result.toJson(),
  };
}

/// `error`: a server refuses an operation; nothing follows it.
@internal
final class const ErrorMessage(
  /// The operation's id.
  final String id,

  /// The errors, at least one.
  final List<GraphQLError> errors,
) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'error';

  @override
  Map<String, JsonValue> get members => {
    'id': JsonString(id),
    'payload': JsonArray([for (final error in errors) error.toJson()]),
  };
}

/// `complete`: a server ends an operation, or a client stops one.
@internal
final class const CompleteMessage(
  /// The operation's id.
  final String id,
) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'complete';

  @override
  Map<String, JsonValue> get members => {'id': JsonString(id)};
}
