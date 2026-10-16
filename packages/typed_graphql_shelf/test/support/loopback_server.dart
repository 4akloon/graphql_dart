import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// A shelf handler served on a free loopback port, for a test to close.
final class LoopbackServer {
  LoopbackServer._(this._server);

  /// Starts serving [handler] on port 0.
  static Future<LoopbackServer> start(Handler handler) async =>
      LoopbackServer._(
        await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0),
      );

  final HttpServer _server;

  /// The port the server listens on.
  int get port => _server.port;

  /// The HTTP address of the server.
  Uri get httpUri => Uri.parse('http://127.0.0.1:${_server.port}/graphql');

  /// The WebSocket address of the server.
  Uri get webSocketUri => Uri.parse('ws://127.0.0.1:${_server.port}/graphql');

  /// Stops the server and ends the connections still open.
  Future<void> close() => _server.close(force: true);
}
