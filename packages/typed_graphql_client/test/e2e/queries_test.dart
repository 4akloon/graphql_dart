import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'support/e2e_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_schema.dart';
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
      ),
    );
  });

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  group('queries over the pipeline', () {
    test('a query with variables gives the data', () async {
      final response = await client.query(const GreetQuery('Ada'));
      expect(response, isA<GraphQLData<String>>());
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
      expect(response.hasErrors, isFalse);
    });

    test('the variables reach the server as JSON', () async {
      await client.query(const GreetQuery('Ada'));
      expect(
        transport.served.single.params.variables,
        JsonObject({'name': const JsonString('Ada')}),
      );
    });

    test('a mutation over POST gives the data', () async {
      final response = await client.mutate(const RenameMutation('Grace'));
      expect((response as GraphQLData<String>).data, 'Grace');
      expect(transport.served.single.method, 'POST');
    });

    test('a failing field gives the data with the error', () async {
      final response = await client.query(const PartialQuery());
      final data = response as GraphQLData<String>;
      expect(data.data, 'hello');
      expect(data.errors.map(codeOf), [TestSchema.brokenCode]);
    });

    test('an unknown field gives the errors with the code', () async {
      final response = await client.query(const UnknownFieldQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL205']);
    });
  });
}
