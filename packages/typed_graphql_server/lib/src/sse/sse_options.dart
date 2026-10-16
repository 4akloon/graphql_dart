/// The settings of the event streams of `GraphQLHttpHandler` (R5.8).
///
/// {@category sse}
final class SseOptions {
  /// Creates the options; the defaults suit a public endpoint.
  const SseOptions({this.keepAliveInterval = const Duration(seconds: 12)});

  /// How long an event stream may stay silent before the server writes a
  /// comment, which keeps proxies and load balancers from closing an idle
  /// connection.
  final Duration keepAliveInterval;
}
