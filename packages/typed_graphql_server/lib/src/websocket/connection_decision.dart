import 'package:typed_graphql/typed_graphql.dart';

/// The answer of a `ConnectionHook`: [AcceptConnection] or
/// [RefuseConnection].
///
/// {@category websocket}
sealed class ConnectionDecision {
  const ConnectionDecision();
}

/// The connection may proceed: the server sends `connection_ack`.
///
/// {@category websocket}
final class AcceptConnection extends ConnectionDecision {
  /// Creates the decision; [payload] is the `connection_ack` payload.
  const AcceptConnection({this.payload});

  /// What the acknowledgement carries, null for none.
  final JsonObject? payload;
}

/// The connection is refused: the server closes it with `4403`.
///
/// {@category websocket}
final class RefuseConnection extends ConnectionDecision {
  /// Creates the decision.
  const RefuseConnection();
}
