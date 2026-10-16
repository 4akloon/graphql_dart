import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_server.dart';

void main() {
  final uri = Uri.parse('http://localhost/graphql');

  group('AuthLink with a refresh', () {
    late PipelineTransport transport;
    late GraphQLClient client;
    late String token;
    late int refreshes;

    setUp(() {
      token = 'stale';
      refreshes = 0;
      transport = PipelineTransport(
        const TestServer().build(),
        isAuthorized: (authorization) => authorization == 'Bearer fresh',
      );
      client = GraphQLClient(
        link: Link.from([
          AuthLink(
            token: () => token,
            refresh: () async {
              refreshes++;
              return token = 'fresh';
            },
          ),
          HttpLink(uri: uri, transport: transport),
        ]),
      );
    });

    test('a stale token is refreshed and the query succeeds', () async {
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
      expect(
        transport.served.map((request) => request.headers['authorization']),
        ['Bearer stale', 'Bearer fresh'],
      );
    });

    test('two queries at the same time refresh once', () async {
      final responses = await Future.wait([
        client.query(const HelloQuery()),
        client.query(const GreetQuery('Ada')),
      ]);
      expect(responses.every((response) => response is GraphQLData), isTrue);
      expect(refreshes, 1);
    });
  });

  group('DedupeLink', () {
    test('two identical queries at the same time reach the server once', () {
      final transport = PipelineTransport(const TestServer().build());
      final client = GraphQLClient(
        link: Link.from([
          DedupeLink(),
          HttpLink(uri: uri, transport: transport),
        ]),
      );
      return Future.wait([
        client.query(const GreetQuery('Ada')),
        client.query(const GreetQuery('Ada')),
      ]).then((responses) {
        expect(responses.whereType<GraphQLData<String>>(), hasLength(2));
        expect(transport.served, hasLength(1));
      });
    });
  });
}
