import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/websocket/socket_session.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../../server/support/server_fixture.dart';
import 'fake_socket.dart';

/// A server fixture with sockets and sessions on top of it.
final class WsFixture {
  WsFixture({this.options = const GraphQLWsOptions()});

  final GraphQLWsOptions options;
  final ServerFixture fixture = ServerFixture();

  /// How many times the context factory ran.
  int contexts = 0;

  /// The connection parameters the context factory saw, per run.
  final List<JsonObject?> seenParams = [];

  /// An upgrade request with [headers].
  RequestInfo upgrade({Map<String, String> headers = const {}}) => RequestInfo(
    method: 'GET',
    uri: Uri.parse('/graphql'),
    headers: headers,
  );

  /// A server whose context factory counts its runs.
  GraphQLServer<Ctx> server() => fixture.server(
    contextFactory: (info) {
      contexts++;
      seenParams.add(info.connectionParams);
      return const Ctx('connection');
    },
  );

  /// A session over [socket]; the future completes when it ends.
  Future<void> run(
    FakeSocket socket, {
    GraphQLServer<Ctx>? server,
    GraphQLWsOptions? options,
    RequestInfo? upgrade,
  }) => SocketSession<Ctx>(
    server: server ?? this.server(),
    options: options ?? this.options,
    socket: socket,
    upgrade: upgrade ?? this.upgrade(),
  ).run();

  /// Sends `connection_init` and waits for the next message.
  Future<Map<String, Object?>> init(
    FakeSocket socket, {
    Map<String, Object?>? payload,
  }) {
    socket.receive(
      jsonEncode({'type': 'connection_init', 'payload': ?payload}),
    );
    return socket.nextSent();
  }

  /// Sends a `subscribe` message.
  void subscribe(FakeSocket socket, String id, String query) => socket.receive(
    jsonEncode({
      'type': 'subscribe',
      'id': id,
      'payload': {'query': query},
    }),
  );
}
