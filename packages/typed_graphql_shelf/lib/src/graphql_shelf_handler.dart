import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'json_refusal.dart';
import 'request_conversion.dart';
import 'response_conversion.dart';
import 'web_socket_upgrade.dart';

/// Serves GraphQL over HTTP and WebSocket as a shelf `Handler` (R5.9).
///
/// It converts each shelf [Request] for a [GraphQLHttpHandler] and writes the
/// answer as a [Response]; with `webSocket` set, a WebSocket upgrade becomes
/// a graphql-ws session instead. Routing, CORS and middleware stay with
/// shelf, so mount it where the endpoint lives, for example with
/// `Router.all`.
///
/// {@category shelf}
final class GraphQLShelfHandler<C> {
  /// Creates a handler that sends requests to [server] under the limits and
  /// settings of [http].
  ///
  /// A `GET` that asks to upgrade to a WebSocket is served as graphql-ws under
  /// [webSocket] when it is given, with WebSocket ping frames every
  /// [webSocketPingInterval]; without it, such a request is an ordinary `GET`.
  /// A WebSocket frame may carry at most what a message of
  /// `webSocket.maxMessageLength` characters takes, or the socket is closed
  /// (`dart:io` sends `1002`) before the frame is buffered.
  ///
  /// Throws an `ArgumentError` when [http] or [webSocket] holds a limit that
  /// makes no sense, or when [webSocketPingInterval] is zero or negative.
  GraphQLShelfHandler(
    GraphQLServer<C> server, {
    HttpOptions http = const HttpOptions(),
    GraphQLWsOptions? webSocket,
    Duration webSocketPingInterval = const Duration(seconds: 12),
  }) : _http = GraphQLHttpHandler<C>(server, options: http),
       _onError = http.onError,
       _upgrade = _upgradeFor<C>(
         server,
         webSocket,
         webSocketPingInterval,
         http.onError,
       );

  final GraphQLHttpHandler<C> _http;
  final ErrorHook? _onError;
  final WebSocketUpgrade<C>? _upgrade;

  static WebSocketUpgrade<C>? _upgradeFor<C>(
    GraphQLServer<C> server,
    GraphQLWsOptions? options,
    Duration pingInterval,
    ErrorHook? onError,
  ) {
    if (pingInterval <= Duration.zero) {
      throw ArgumentError.value(
        pingInterval,
        'webSocketPingInterval',
        'must be positive',
      );
    }
    if (options == null) return null;
    return WebSocketUpgrade<C>(
      GraphQLWsHandler<C>(server, options: options),
      pingInterval,
      options.maxMessageLength,
      onError,
    );
  }

  /// Answers [request]; it never throws. What it did not expect, such as a
  /// request whose body a middleware already read or one that cannot be
  /// upgraded, is answered `500` with `GQL330` and reported to
  /// `HttpOptions.onError`.
  FutureOr<Response> call(Request request) async {
    try {
      return await _serve(request);
    } on HijackException {
      // Control flow of shelf: the upgrade took the connection.
      rethrow;
    } on Object catch (error, stackTrace) {
      // The boundary of the adapter, like `GraphQLHttpHandler.handle`: a bug
      // or a host that cannot do what was asked is a response, reported to
      // the hook, never rethrown.
      return _failed(error, stackTrace);
    }
  }

  FutureOr<Response> _serve(Request request) async {
    final upgrade = _upgrade;
    if (upgrade != null && upgrade.isUpgrade(request)) {
      return upgrade.handle(request);
    }
    return const ResponseConversion().convert(
      await _http.handle(const RequestConversion().convert(request)),
    );
  }

  Response _failed(Object error, StackTrace stackTrace) {
    const refusal = JsonRefusal();
    var reported = refusal.error(
      DiagnosticCode.unexpectedError,
      'The request could not be handled.',
    );
    final hook = _onError;
    if (hook != null) {
      try {
        reported = hook(error, stackTrace, reported) ?? reported;
      } on Object {
        // A faulty hook must not turn the report into a failure.
      }
    }
    return refusal.withError(500, reported);
  }
}
