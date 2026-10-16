import 'package:meta/meta.dart';

/// The WebSocket close codes and fixed reasons of the graphql-ws handler.
///
/// A reason never echoes the client's text (spec M7 §17).
@internal
enum WsClose(
  /// The WebSocket close code.
  final int code,

  /// The reason, a fixed text of at most 123 UTF-8 bytes.
  final String reason,
) {
  /// A message that is not a valid client message (`4400`).
  invalidMessage(4400, 'Invalid message received'),

  /// A `subscribe` before the connection was acknowledged (`4401`).
  unauthorized(4401, 'Unauthorized'),

  /// The connection hook refused, or the Origin did (`4403`).
  forbidden(4403, 'Forbidden'),

  /// The subprotocol is not `graphql-transport-ws` (`4406`).
  subprotocolNotAcceptable(4406, 'Subprotocol not acceptable'),

  /// No acknowledgement within the timeout (`4408`).
  initTimeout(4408, 'Connection initialisation timeout'),

  /// A second `connection_init` (`4429`).
  tooManyInits(4429, 'Too many initialisation requests'),

  /// The connection hook threw (`4500`).
  internalError(4500, 'Internal server error'),

  /// A frame over the length limit (`1009`).
  messageTooBig(1009, 'Message too big'),

  /// More connections than the handler serves (`1013`).
  tryAgainLater(1013, 'Try again later'),
}
