import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_server.dart';

void main() {
  late PipelineTransport transport;
  late GraphQLClient client;

  setUp(() {
    transport = PipelineTransport(const TestServer().build());
    client = GraphQLClient(
      link: HttpLink(
        uri: Uri.parse('http://localhost/graphql'),
        transport: transport,
        usesGetForQueries: true,
      ),
    );
  });

  group('GET queries over the pipeline', () {
    test('a query goes as GET with the preflight header', () async {
      await client.query(const GreetQuery('Ada'));
      final served = transport.served.single;
      expect(served.method, 'GET');
      expect(served.headers['graphql-require-preflight'], 'true');
    });

    test('CSRF prevention accepts the GET query', () async {
      final response = await client.query(const GreetQuery('Ada'));
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
    });

    test('the variables travel in the query string', () async {
      await client.query(const GreetQuery('Ada'));
      expect(
        transport.served.single.uri.queryParameters['variables'],
        '{"name":"Ada"}',
      );
    });

    test('a mutation through the same link goes as POST', () async {
      final response = await client.mutate(const RenameMutation('Grace'));
      expect((response as GraphQLData<String>).data, 'Grace');
      expect(transport.served.single.method, 'POST');
    });
  });
}
