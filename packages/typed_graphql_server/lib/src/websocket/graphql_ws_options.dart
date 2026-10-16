import 'connection_hook.dart';

/// The limits and hooks of a `GraphQLWsHandler` (R5.7).
///
/// {@category websocket}
final class GraphQLWsOptions {
  /// Creates options; the handler checks that the durations and limits are
  /// positive and that [maxJsonDepth] is supported.
  const GraphQLWsOptions({
    this.connectionInitTimeout = const Duration(seconds: 3),
    this.maxOperations = 100,
    this.maxMessageLength = 1048576,
    this.maxJsonDepth = 64,
    this.maxConnections = 10000,
    this.allowedOrigins,
    this.onConnect,
  });

  /// How long a connection may stay open without being acknowledged; past it
  /// the server closes `4408`.
  final Duration connectionInitTimeout;

  /// The most operations one connection runs at once; a `subscribe` past it
  /// is answered with an `error` message (`GQL432`) and the socket stays open.
  final int maxOperations;

  /// The longest frame accepted, in UTF-16 code units, checked before the
  /// text is parsed; a longer one closes `1009`.
  final int maxMessageLength;

  /// The deepest JSON nesting accepted in a frame (`JsonReader.maxDepth`); a
  /// deeper one closes `4400`.
  final int maxJsonDepth;

  /// The most connections one handler serves at once; past it a new one is
  /// closed `1013`.
  final int maxConnections;

  /// The origins, besides the upgrade's own host, whose WebSocket upgrades
  /// are accepted (exact match, ignoring case); null lists none. A browser
  /// sends cookies with an upgrade, so this is the CSRF defence of the
  /// transport.
  final List<String>? allowedOrigins;

  /// Runs when `connection_init` arrives and decides whether to acknowledge;
  /// null acknowledges every connection.
  final ConnectionHook? onConnect;
}
