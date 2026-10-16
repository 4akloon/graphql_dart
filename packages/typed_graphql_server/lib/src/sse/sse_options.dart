import 'single_connection_options.dart';

/// The settings of the event streams of `GraphQLHttpHandler` (R5.8).
///
/// {@category sse}
final class SseOptions {
  /// Creates the options; the defaults suit a public endpoint.
  const SseOptions({
    this.keepAliveInterval = const Duration(seconds: 12),
    this.singleConnection,
  });

  /// How long an event stream may stay silent before the server writes a
  /// comment, which keeps proxies and load balancers from closing an idle
  /// connection.
  final Duration keepAliveInterval;

  /// The limits of single connection mode, or null, the default, to leave the
  /// mode off: a `PUT` is then `405` and a token is ignored.
  final SingleConnectionOptions? singleConnection;
}
