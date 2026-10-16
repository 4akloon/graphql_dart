import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/test_operations.dart';
import 'support/e2e_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_server.dart';

void main() {
  final uri = Uri.parse('http://localhost/graphql');

  GraphQLClient clientOver(PipelineTransport transport, Link persisted) =>
      GraphQLClient(
        link: Link.from([persisted, HttpLink(uri: uri, transport: transport)]),
      );

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  group('automatic persisted queries', () {
    late PipelineTransport transport;
    late GraphQLClient client;

    setUp(() {
      transport = PipelineTransport(
        const TestServer().build(persistedQueries: MemoryPersistedQueryStore()),
      );
      client = clientOver(transport, PersistedQueryLink());
    });

    test('the first query is a miss, then a resend with the text', () async {
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
      expect(transport.served.map((request) => request.params.query), [
        isNull,
        HelloQuery.operationDocument.text,
      ]);
    });

    test('the second identical query sends the hash alone', () async {
      await client.query(const HelloQuery());
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
      expect(transport.served, hasLength(3));
      expect(transport.served.last.params.query, isNull);
    });
  });

  group('a server without a store', () {
    test('answers not supported and the link switches to text', () async {
      final transport = PipelineTransport(const TestServer().build());
      final client = clientOver(transport, PersistedQueryLink());
      final first = await client.query(const HelloQuery());
      await client.query(const HelloQuery());
      expect((first as GraphQLData<String>).data, 'hello');
      expect(transport.served.map((request) => request.params.query), [
        isNull,
        HelloQuery.operationDocument.text,
        HelloQuery.operationDocument.text,
      ]);
    });
  });

  group('trusted documents', () {
    late PipelineTransport transport;
    late GraphQLClient client;

    setUp(() {
      final manifest = const JsonReader().parse(
        jsonEncode({
          'format': 'apollo-persisted-query-manifest',
          'version': 1,
          'operations': [
            {
              'id': HelloQuery.operationDocument.sha256,
              'name': 'Hello',
              'type': 'query',
              'body': HelloQuery.operationDocument.text,
            },
          ],
        }),
      );
      final trusted = switch (manifest) {
        DecodeSuccess(:final value) => switch (TrustedDocuments.decode(value)) {
          DecodeSuccess(:final value) => value,
          DecodeFailure(:final message) => throw StateError(message),
        },
        DecodeFailure(:final message) => throw StateError(message),
      };
      transport = PipelineTransport(
        const TestServer().build(trustedDocuments: trusted),
      );
      client = clientOver(transport, PersistedQueryLink(isAutomatic: false));
    });

    test('a trusted query succeeds with the hash alone', () async {
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
      expect(transport.served.single.params.query, isNull);
    });

    test('an untrusted query gives GQL415', () async {
      final response = await client.query(const PartialQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL415']);
    });
  });
}
