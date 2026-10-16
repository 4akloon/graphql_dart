@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';
import 'package:web_socket_channel/io.dart';

import 'support/frame_reader.dart';
import 'support/loopback_server.dart';
import 'support/shelf_fixture.dart';

void main() {
  final fixture = ShelfFixture();
  late LoopbackServer server;

  Future<void> serve({
    GraphQLWsOptions options = const GraphQLWsOptions(),
  }) async {
    server = await LoopbackServer.start(
      GraphQLShelfHandler<Object?>(fixture.server(), webSocket: options).call,
    );
  }

  Future<FrameReader> connect({
    List<String>? protocols = const [GraphQLWsHandler.protocol],
    Map<String, Object>? headers,
  }) async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      protocols: protocols,
      headers: headers,
    );
    await channel.ready;
    return FrameReader(channel);
  }

  tearDown(() => server.close());

  test('acknowledges connection_init', () async {
    await serve();
    final client = await connect();
    client.send({'type': 'connection_init'});
    expect((await client.next())['type'], 'connection_ack');
  });

  test('streams a subscription as next then complete', () async {
    await serve();
    final client = await connect();
    client.send({'type': 'connection_init'});
    await client.next();
    client.send({
      'id': '1',
      'type': 'subscribe',
      'payload': {'query': 'subscription { ticks }'},
    });
    final received = [for (var i = 0; i < 3; i++) await client.next()];
    expect(received, [
      {
        'id': '1',
        'type': 'next',
        'payload': {
          'data': {'ticks': 'tick 1'},
        },
      },
      {
        'id': '1',
        'type': 'next',
        'payload': {
          'data': {'ticks': 'tick 2'},
        },
      },
      {'id': '1', 'type': 'complete'},
    ]);
  });

  test('answers a query sent over the socket', () async {
    await serve();
    final client = await connect();
    client.send({'type': 'connection_init'});
    await client.next();
    client.send({
      'id': 'q',
      'type': 'subscribe',
      'payload': {'query': '{ hello }'},
    });
    expect((await client.next())['payload'], {
      'data': {'hello': 'world'},
    });
  });

  test('closes 4406 when the client offers no known subprotocol', () async {
    await serve();
    final client = await connect(protocols: null);
    expect(await client.closeCode(), 4406);
  });

  test('closes 4400 on a binary frame that is not JSON', () async {
    await serve();
    final client = await connect();
    client.send({'type': 'connection_init'});
    await client.next();
    client.channel.sink.add([0xFF, 0xFE]);
    expect(await client.closeCode(), 4400);
  });

  test('refuses an upgrade from a foreign origin with 403', () async {
    await serve();
    final http = HttpClient();
    addTearDown(http.close);
    final request = await http.getUrl(server.httpUri);
    request.headers
      ..set('connection', 'Upgrade')
      ..set('upgrade', 'websocket')
      ..set('sec-websocket-version', '13')
      ..set('sec-websocket-key', base64Encode(List.filled(16, 1)))
      ..set('origin', 'http://evil.example');
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, 403);
  });

  test('accepts an origin listed in allowedOrigins', () async {
    await serve(
      options: const GraphQLWsOptions(allowedOrigins: ['http://app.example']),
    );
    final client = await connect(headers: {'origin': 'http://app.example'});
    client.send({'type': 'connection_init'});
    expect((await client.next())['type'], 'connection_ack');
  });

  test('negotiates the graphql-transport-ws subprotocol', () async {
    await serve();
    final client = await connect();
    expect(client.channel.protocol, GraphQLWsHandler.protocol);
  });

  test('sends WebSocket ping frames at the configured interval', () async {
    server = await LoopbackServer.start(
      GraphQLShelfHandler<Object?>(
        fixture.server(),
        webSocket: const GraphQLWsOptions(),
        webSocketPingInterval: const Duration(milliseconds: 30),
      ).call,
    );
    final client = await connect();
    client.send({'type': 'connection_init'});
    await client.next();
    // A ping the client does not answer would end the connection; the pong
    // dart:io sends by itself keeps it open past several intervals.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(client.channel.closeCode, isNull);
  });
}
