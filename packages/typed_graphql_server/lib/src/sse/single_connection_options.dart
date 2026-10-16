/// The limits of single connection mode, in which one event stream carries
/// the results of many operations (R5.8).
///
/// State lives in the handler, so a host with several instances needs sticky
/// sessions: every request of a stream must reach the instance that holds its
/// reservation.
///
/// {@category sse}
final class SingleConnectionOptions {
  /// Creates the options; the defaults suit a public endpoint.
  const SingleConnectionOptions({
    this.maxReservations = 1000,
    this.reservationTimeout = const Duration(seconds: 30),
    this.maxOperationsPerStream = 100,
  });

  /// How many reservations the handler holds at once; a `PUT` past it is
  /// refused with `503` (`GQL437`).
  final int maxReservations;

  /// How long a reservation waits for its stream to connect before it is
  /// dropped, with the operations posted meanwhile.
  final Duration reservationTimeout;

  /// How many operations one stream runs or holds at once; one past it is
  /// refused with `409` (`GQL438`).
  final int maxOperationsPerStream;
}
