import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_transport.dart';
import '../support/test_operations.dart';

void main() {
  late FakeTransport transport;

  setUp(() => transport = FakeTransport()..answer('{"data":{"greet":"hi"}}'));

  HttpLink linkTo(String uri) => HttpLink(
    uri: Uri.parse(uri),
    transport: transport,
    usesGetForQueries: true,
  );

  Future<void> send(HttpLink link, LinkRequest request) =>
      link.request(request, (request) => const Stream.empty()).drain<void>();

  test('sends a query as a GET with its fields as parameters', () async {
    await send(
      linkTo('https://example.com/graphql'),
      LinkRequest.of(const GreetQuery('Ann')),
    );
    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.queryParameters, {
      'query': r'query Greet($name:String!){greet(name:$name)}',
      'operationName': 'Greet',
      'variables': '{"name":"Ann"}',
    });
    expect(request.body, isNull);
  });

  test('adds the preflight header and no content type', () async {
    await send(
      linkTo('https://example.com/graphql'),
      LinkRequest.of(const HelloQuery()),
    );
    expect(transport.requests.single.headers, {
      'accept': 'application/graphql-response+json, application/json;q=0.9',
      'graphql-require-preflight': 'true',
    });
  });

  test("keeps the URI's own parameters", () async {
    await send(
      linkTo('https://example.com/graphql?tenant=a'),
      LinkRequest.of(const HelloQuery()),
    );
    expect(transport.requests.single.uri.queryParameters['tenant'], 'a');
  });

  test('sends the hash alone without a query parameter', () async {
    await send(
      linkTo('https://example.com/graphql'),
      LinkRequest.of(const HelloQuery())
          .withExtensions(
            JsonObject({
              'persistedQuery': JsonObject({'version': JsonNumber(1)}),
            }),
          )
          .withDocumentText(sendsDocumentText: false),
    );
    final parameters = transport.requests.single.uri.queryParameters;
    expect(parameters.containsKey('query'), isFalse);
    expect(jsonDecode(parameters['extensions']!), {
      'persistedQuery': {'version': 1},
    });
  });

  test('sends a mutation as a POST', () async {
    await send(
      linkTo('https://example.com/graphql'),
      LinkRequest.of(const RenameMutation('Ada')),
    );
    expect(transport.requests.single.method, 'POST');
  });
}
