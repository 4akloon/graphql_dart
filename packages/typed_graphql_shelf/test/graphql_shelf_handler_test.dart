import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

import 'support/shelf_fixture.dart';

void main() {
  final fixture = ShelfFixture();
  final uri = Uri.parse('http://example.test/graphql');

  Future<Response> send(
    Request request, {
    ServerProfile profile = ServerProfile.development,
  }) async => await GraphQLShelfHandler<Object?>(
    fixture.server(profile: profile),
  )(request);

  Request post(String query) => Request(
    'POST',
    uri,
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'query': query}),
  );

  test('answers a query posted as JSON', () async {
    final response = await send(post('{ hello }'));
    expect(response.statusCode, 200);
    expect(await response.readAsString(), '{"data":{"hello":"world"}}');
  });

  test('answers a mutation posted as JSON', () async {
    final response = await send(post('mutation { bump }'));
    expect(await response.readAsString(), '{"data":{"bump":"bumped"}}');
  });

  test('answers a query in a GET', () async {
    final response = await send(
      Request(
        'GET',
        uri.replace(queryParameters: {'query': '{ hello }'}),
        headers: {'graphql-require-preflight': 'true'},
      ),
    );
    expect(await response.readAsString(), '{"data":{"hello":"world"}}');
  });

  test('refuses a PUT with 405 and the allowed methods', () async {
    final response = await send(Request('PUT', uri));
    expect(response.statusCode, 405);
    expect(response.headers['allow'], 'GET, POST');
  });

  test('writes the media type of the result', () async {
    final response = await send(post('{ hello }'));
    expect(response.mimeType, 'application/json');
  });

  test('serves the GraphiQL page to a browser in development', () async {
    final response = await send(
      Request('GET', uri, headers: {'accept': 'text/html'}),
    );
    expect(response.mimeType, 'text/html');
  });

  test('does not serve the GraphiQL page in production', () async {
    final response = await send(
      Request('GET', uri, headers: {'accept': 'text/html'}),
      profile: ServerProfile.production,
    );
    expect(response.mimeType, isNot('text/html'));
  });

  test('is a shelf Handler', () {
    final Handler handler = GraphQLShelfHandler<Object?>(fixture.server()).call;
    expect(handler, isNotNull);
  });
}
