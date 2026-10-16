@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';
import 'package:web_socket_channel/io.dart';

import 'support/end_to_end_fixture.dart';
import 'support/frame_reader.dart';
import 'support/loopback_server.dart';

void main() {
  late EndToEndFixture fixture;
  late LoopbackServer server;
  late HttpClient client;

  setUp(() async {
    fixture = EndToEndFixture();
    client = HttpClient();
    server = await LoopbackServer.start(
      GraphQLShelfHandler<Object?>(
        fixture.server(),
        webSocket: const GraphQLWsOptions(),
      ).call,
    );
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    await fixture.close();
  });

  test('delivers the first server-sent event before the second exists', () async {
    final request = await client.postUrl(server.httpUri);
    request.headers
      ..set('content-type', 'application/json')
      ..set('accept', 'text/event-stream')
      ..set('graphql-require-preflight', 'true');
    request.add(utf8.encode(jsonEncode({'query': 'subscription { ticks }'})));
    final response = await request.close();
    final lines = StreamIterator(
      response.transform(utf8.decoder).transform(const LineSplitter()),
    );
    Future<String> nextData() async {
      while (await lines.moveNext().timeout(const Duration(seconds: 5))) {
        if (lines.current.startsWith('data:')) return lines.current;
      }
      throw StateError('The stream ended.');
    }

    // The subscription listens after the response starts; emit until it hears.
    final emitter = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => fixture.ticks.hasListener ? fixture.ticks.add(1) : null,
    );
    final first = await nextData();
    emitter.cancel();
    expect(response.headers.contentType?.mimeType, 'text/event-stream');
    expect(first, contains('"ticks":"tick 1"'));
    fixture.ticks.add(2);
    expect(await nextData(), contains('"ticks":"tick 2"'));
    await lines.cancel();
  });

  test('streams a graphql-ws subscription over a real socket', () async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      protocols: const [GraphQLWsHandler.protocol],
    );
    await channel.ready;
    final reader = FrameReader(channel);
    reader.send({'type': 'connection_init'});
    expect((await reader.next())['type'], 'connection_ack');
    reader.send({
      'id': '1',
      'type': 'subscribe',
      'payload': {'query': 'subscription { ticks }'},
    });
    final emitter = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => fixture.ticks.hasListener ? fixture.ticks.add(7) : null,
    );
    final message = await reader.next();
    emitter.cancel();
    expect(message, {
      'id': '1',
      'type': 'next',
      'payload': {
        'data': {'ticks': 'tick 7'},
      },
    });
    await channel.sink.close();
  });
}
