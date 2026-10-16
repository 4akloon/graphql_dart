import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../e2e/support/e2e_operations.dart';
import '../e2e/support/test_server.dart';
import '../support/test_operations.dart';
import 'support/handler_transport.dart';

void main() {
  final uri = Uri.parse('http://localhost/graphql');

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  ({GraphQLClient client, HandlerTransport transport}) clientOver(
    GraphQLServer<Object?> server, {
    HttpOptions options = const HttpOptions(),
    bool usesGetForQueries = false,
    Link? before,
  }) {
    final transport = HandlerTransport(
      GraphQLHttpHandler<Object?>(server, options: options),
    );
    final http = HttpLink(
      uri: uri,
      transport: transport,
      usesGetForQueries: usesGetForQueries,
    );
    final link = before == null ? http : Link.from([before, http]);
    return (client: GraphQLClient(link: link), transport: transport);
  }

  group('HttpLink against the M7 handler', () {
    test('a query is a 200 graphql-response+json with the data', () async {
      final (:client, :transport) = clientOver(const TestServer().build());
      final response = await client.query(const GreetQuery('Ada'));
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
      expect(transport.statuses, [200]);
      expect(
        transport.contentTypes.single,
        startsWith('application/graphql-response+json'),
      );
    });

    test('a partial result is a 294 the client reads as data', () async {
      final (:client, :transport) = clientOver(const TestServer().build());
      final response = await client.query(const PartialQuery());
      final data = response as GraphQLData<String>;
      expect(data.data, 'hello');
      expect(data.errors, hasLength(1));
      expect(transport.statuses, [294]);
    });

    test('a validation error is a 422 the client reads as errors', () async {
      final (:client, :transport) = clientOver(const TestServer().build());
      final response = await client.query(const UnknownFieldQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL205']);
      expect(transport.statuses, [422]);
    });

    test('a GET query with the preflight header passes', () async {
      final (:client, :transport) = clientOver(
        const TestServer().build(),
        usesGetForQueries: true,
      );
      final response = await client.query(const HelloQuery());
      expect(response, isA<GraphQLData<String>>());
      expect(transport.methods, ['GET']);
      expect(transport.statuses, [200]);
    });

    test('a mutation over POST gives the data', () async {
      final (:client, :transport) = clientOver(const TestServer().build());
      final response = await client.mutate(const RenameMutation('Grace'));
      expect((response as GraphQLData<String>).data, 'Grace');
      expect(transport.methods, ['POST']);
    });

    test('a body over the limit is a 413 transport failure', () async {
      final (:client, :transport) = clientOver(
        const TestServer().build(),
        options: const HttpOptions(maxBodyBytes: 64),
      );
      final response = await client.query(GreetQuery('a' * 100));
      final failure = (response as GraphQLTransportFailure<String>).failure;
      expect(failure, isA<HttpStatusFailure>());
      expect((failure as HttpStatusFailure).statusCode, 413);
    });

    test('automatic persisted queries reach the store in M7', () async {
      final (:client, :transport) = clientOver(
        const TestServer().build(
          persistedQueries: MemoryPersistedQueryStore(),
        ),
        before: PersistedQueryLink(),
      );
      await client.query(const HelloQuery());
      final second = await client.query(const HelloQuery());
      expect(second, isA<GraphQLData<String>>());
      // A miss and the text, then the hash alone.
      expect(transport.statuses, hasLength(3));
    });
  });
}
