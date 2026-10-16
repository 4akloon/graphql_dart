import 'package:meta/meta.dart';

/// How one socket's life ended, as `SocketConnection.run` reports it.
@internal
sealed class SocketEnd {
  /// Creates an end.
  const SocketEnd();
}

/// The socket closed or failed, by the server, the network or the link's
/// own keep-alive; the reconnection rules decide what follows.
@internal
final class const ConnectionLost({
  /// The close code, when the socket gave one.
  final int? closeCode,

  /// The close reason, when the socket gave one.
  final String? closeReason,

  /// What the messages stream failed with, when it failed.
  final Object? cause,
}) extends SocketEnd {
  /// Creates the end.
  this;

  /// What happened, as a sentence.
  String get message {
    if (cause != null) {
      return 'The socket failed: $cause';
    }
    final reason = closeReason;
    final suffix = reason == null || reason.isEmpty ? '' : ': $reason';
    return closeCode == null
        ? 'The socket closed.'
        : 'The socket closed with code $closeCode$suffix';
  }
}

/// The server did not send `connection_ack` in time (`GQL472`).
@internal
final class const AckTimedOut() extends SocketEnd {
  /// Creates the end.
  this;
}

/// The server sent a message the protocol does not allow (`GQL470`).
@internal
final class const MalformedMessage(
  /// What was wrong with it.
  final String reason,
) extends SocketEnd {
  /// Creates the end.
  this;
}
