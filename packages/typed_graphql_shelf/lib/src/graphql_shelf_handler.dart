import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

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
  ///
  /// Throws an `ArgumentError` when [http] or [webSocket] holds a limit that
  /// makes no sense.
  GraphQLShelfHandler(
    GraphQLServer<C> server, {
    HttpOptions http = const HttpOptions(),
    GraphQLWsOptions? webSocket,
    Duration webSocketPingInterval = const Duration(seconds: 12),
  }) : _http = GraphQLHttpHandler<C>(server, options: http),
       _upgrade = webSocket == null
           ? null
           : WebSocketUpgrade<C>(
               GraphQLWsHandler<C>(server, options: webSocket),
               webSocketPingInterval,
             );

  final GraphQLHttpHandler<C> _http;
  final WebSocketUpgrade<C>? _upgrade;

  /// Answers [request]; it never throws.
  FutureOr<Response> call(Request request) async {
    final upgrade = _upgrade;
    if (upgrade != null && upgrade.isUpgrade(request)) {
      return upgrade.handle(request);
    }
    return const ResponseConversion().convert(
      await _http.handle(const RequestConversion().convert(request)),
    );
  }
}
