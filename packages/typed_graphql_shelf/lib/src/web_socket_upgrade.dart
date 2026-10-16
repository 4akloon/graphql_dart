import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'request_conversion.dart';
import 'web_socket_channel_socket.dart';

/// Turns a WebSocket upgrade into a graphql-ws session.
@internal
final class WebSocketUpgrade<C> {
  /// Creates the upgrade for [_handler], with WebSocket ping frames every
  /// [_pingInterval].
  WebSocketUpgrade(this._handler, this._pingInterval);

  final GraphQLWsHandler<C> _handler;
  final Duration _pingInterval;

  /// Whether [request] asks to become a WebSocket.
  bool isUpgrade(Request request) =>
      request.method == 'GET' &&
      request.headers['upgrade']?.toLowerCase() == 'websocket';

  /// Answers the upgrade [request]: a `403` when its `Origin` is not allowed
  /// (a browser sends cookies with an upgrade and no preflight, spec section
  /// 9), else the `101` that `shelf_web_socket` writes before the session.
  FutureOr<Response> handle(Request request) {
    final info = const RequestConversion().info(request);
    if (!_handler.allowsUpgrade(info)) {
      return _forbidden();
    }
    return webSocketHandler(
      (channel, protocol) => unawaited(
        _handler.serve(WebSocketChannelSocket(channel, protocol), info),
      ),
      protocols: const [GraphQLWsHandler.protocol],
      pingInterval: _pingInterval,
    )(request);
  }

  // A transport refusal, JSON like the HTTP handler's, with the CSRF code
  // because this is the CSRF defence of the WebSocket transport.
  Response _forbidden() => Response(
    403,
    body: jsonEncode(
      RequestErrorResult(
        errors: [
          GraphQLError(
            'The Origin of this WebSocket upgrade is not allowed.',
            extensions: JsonObject({
              'code': JsonString(DiagnosticCode.csrfRequestBlocked.id),
            }),
          ),
        ],
      ).toJson(),
    ),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
