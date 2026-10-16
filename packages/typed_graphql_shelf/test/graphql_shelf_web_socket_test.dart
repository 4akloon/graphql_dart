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
import 'support/raw_web_socket.dart';
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
    final client = await RawWebSocket.open(server.port);
    addTearDown(client.destroy);
    // A ping frame is 0x89 and a zero length, the first thing the server
    // writes after the handshake when nobody sent it a message.
    await client
        .until((frames) => frames.length >= 2)
        .timeout(const Duration(seconds: 5));
    expect(client.frames.take(2), [0x89, 0]);
  });

  test('closes the socket on a frame larger than a message may be', () async {
    await serve(options: const GraphQLWsOptions(maxMessageLength: 100));
    final client = await RawWebSocket.open(server.port);
    addTearDown(client.destroy);
    await client.until((_) => client.statusLine != null);
    // The header alone declares 1 MiB; no payload follows, so the close
    // proves the frame was refused before it was buffered.
    client.sendTextHeader(1 << 20);
    await client
        .until((frames) => frames.contains(0x88))
        .timeout(const Duration(seconds: 5));
    final close = client.frames.skipWhile((byte) => byte != 0x88).toList();
    // dart:io answers 1002 (protocol error), not 1009, to such a frame.
    expect(close.sublist(2, 4), [0x03, 0xEA]);
  });

  test('accepts a frame under the limit of a small message', () async {
    await serve(options: const GraphQLWsOptions(maxMessageLength: 100));
    final client = await connect();
    client.send({
      'type': 'connection_init',
      'payload': {'k': 'x' * 40},
    });
    expect((await client.next())['type'], 'connection_ack');
  });

  test(
    'accepts a frame of three bytes per code unit up to the limit',
    () async {
      // The slack of 1024 bytes hides the multiple in a small message, so the
      // message is big: 800 euro signs are about 2.4 KB in UTF-8 but 850 code
      // units, within the limit, and over a frame limit of one byte per unit.
      await serve(options: const GraphQLWsOptions(maxMessageLength: 1000));
      final client = await connect();
      client.send({
        'type': 'connection_init',
        'payload': {'k': '\u20AC' * 800},
      });
      expect((await client.next())['type'], 'connection_ack');
    },
  );
}
