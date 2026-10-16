import 'package:meta/meta.dart';

import 'event_stream.dart';

/// What asking to connect the stream of a token gave.
@internal
sealed class ConnectOutcome {
  const ConnectOutcome();
}

/// The stream is now connected; the host writes [stream].
@internal
final class Connected extends ConnectOutcome {
  /// Creates the outcome for [stream].
  const Connected(this.stream);

  /// The event stream of the reservation.
  final EventStream stream;
}

/// No reservation holds the token (never issued, dropped or closed).
@internal
final class UnknownToken extends ConnectOutcome {
  /// Creates the outcome.
  const UnknownToken();
}

/// The reservation's stream is already connected; only one may be.
@internal
final class AlreadyOpen extends ConnectOutcome {
  /// Creates the outcome.
  const AlreadyOpen();
}
