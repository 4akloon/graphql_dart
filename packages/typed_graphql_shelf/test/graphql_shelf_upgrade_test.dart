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

  GraphQLShelfHandler<Object?> upgrading({
    HttpOptions http = const HttpOptions(),
  }) => GraphQLShelfHandler<Object?>(
    fixture.server(),
    http: http,
    webSocket: const GraphQLWsOptions(),
  );

  Future<Map<String, Object?>> body(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, Object?>;

  String? codeOf(Map<String, Object?> body) =>
      (((body['errors']! as List).single as Map)['extensions'] as Map)['code']
          as String?;

  test('refuses a version other than 13 with a JSON 400', () async {
    final response = await upgrading()(
      upgrade(
        headers: {
          'origin': 'http://example.test',
          'host': 'example.test',
          'sec-websocket-version': '12',
        },
      ),
    );
    expect(response.statusCode, 400);
    expect(response.headers['content-type'], startsWith('application/json'));
    expect(codeOf(await body(response)), 'GQL425');
  });

  test('refuses an upgrade without Connection: Upgrade with JSON', () async {
    final response = await upgrading()(
      Request(
        'GET',
        queryUri,
        headers: {
          'graphql-require-preflight': 'true',
          'upgrade': 'websocket',
          'sec-websocket-version': '13',
          'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==',
        },
      ),
    );
    expect(response.statusCode, 400);
    expect(codeOf(await body(response)), 'GQL425');
  });

  test('refuses an upgrade without a key', () async {
    final response = await upgrading()(
      Request(
        'GET',
        queryUri,
        headers: {
          'connection': 'Upgrade',
          'upgrade': 'websocket',
          'sec-websocket-version': '13',
        },
      ),
    );
    expect(response.statusCode, 400);
  });

  test('answers 500 GQL330 when the request cannot be hijacked', () async {
    Object? reported;
    final response = await upgrading(
      http: HttpOptions(
        onError: (error, stackTrace, standard) {
          reported = error;
          return null;
        },
      ),
    )(upgrade());
    expect(response.statusCode, 500);
    expect(codeOf(await body(response)), 'GQL330');
    expect(reported, isA<StateError>());
  });

  test('answers 500 GQL330 when a middleware already read the body', () async {
    Object? reported;
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      http: HttpOptions(
        onError: (error, stackTrace, standard) {
          reported = error;
          return null;
        },
      ),
    );
    final request = Request('POST', uri, body: '{}');
    await request.read().drain<void>();
    final response = await handler(request);
    expect(response.statusCode, 500);
    expect(codeOf(await body(response)), 'GQL330');
    expect(reported, isA<StateError>());
  });

  test('still answers when the error hook throws', () async {
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      http: HttpOptions(
        onError: (error, stackTrace, standard) => throw StateError('hook'),
      ),
    );
    final request = Request('POST', uri, body: '{}');
    await request.read().drain<void>();
    expect((await handler(request)).statusCode, 500);
  });

  for (final interval in [Duration.zero, const Duration(seconds: -1)]) {
    test('refuses the ping interval $interval', () {
      expect(
        () => GraphQLShelfHandler<Object?>(
          fixture.server(),
          webSocket: const GraphQLWsOptions(),
          webSocketPingInterval: interval,
        ),
        throwsArgumentError,
      );
    });
  }
}
