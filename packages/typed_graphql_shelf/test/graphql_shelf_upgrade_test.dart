import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

import 'support/shelf_fixture.dart';

void main() {
  final fixture = ShelfFixture();
  final uri = Uri.parse('http://example.test/graphql');

  final queryUri = uri.replace(queryParameters: {'query': '{ hello }'});

  Request upgrade({Map<String, String> headers = const {}}) => Request(
    'GET',
    queryUri,
    headers: {
      'graphql-require-preflight': 'true',
      'connection': 'Upgrade',
      'upgrade': 'websocket',
      'sec-websocket-version': '13',
      'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==',
      ...headers,
    },
  );

  test('refuses an upgrade from a foreign origin with 403', () async {
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      webSocket: const GraphQLWsOptions(),
    );
    final response = await handler(
      upgrade(headers: {'origin': 'http://evil.example', 'host': 'a.test'}),
    );
    expect(response.statusCode, 403);
  });

  test('writes the refusal as a JSON error', () async {
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      webSocket: const GraphQLWsOptions(),
    );
    final response = await handler(
      upgrade(headers: {'origin': 'http://evil.example', 'host': 'a.test'}),
    );
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(response.headers['content-type'], startsWith('application/json'));
    expect(((body['errors'] as List).single as Map)['extensions'], {
      'code': 'GQL403',
    });
  });

  test('treats an upgrade as an ordinary GET without webSocket', () async {
    final handler = GraphQLShelfHandler<Object?>(fixture.server());
    final response = await handler(
      upgrade(headers: {'origin': 'http://evil.example'}),
    );
    expect(await response.readAsString(), '{"data":{"hello":"world"}}');
  });

  test('treats a GET without an upgrade as an ordinary GET', () async {
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      webSocket: const GraphQLWsOptions(),
    );
    final response = await handler(
      Request(
        'GET',
        queryUri,
        headers: {'graphql-require-preflight': 'true'},
      ),
    );
    expect(await response.readAsString(), '{"data":{"hello":"world"}}');
  });

  test('hands a same-host upgrade to the WebSocket handler', () async {
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      webSocket: const GraphQLWsOptions(),
    );
    final response = await handler(
      upgrade(
        headers: {
          'origin': 'http://example.test',
          'host': 'example.test',
          'sec-websocket-version': '12',
        },
      ),
    );
    // shelf_web_socket answers 404 to a version it does not speak, which
    // shows the request got past the Origin check.
    expect(response.statusCode, 404);
  });
}
