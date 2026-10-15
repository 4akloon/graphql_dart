import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  const text = '{hello}';
  final hash = fixture.hashOf(text);

  JsonObject manifest(List<JsonValue> operations) => JsonObject({
    'format': const JsonString('apollo-persisted-query-manifest'),
    'version': JsonNumber(1),
    'operations': JsonArray(operations),
  });

  JsonObject entry(String id, String body) => JsonObject({
    'id': JsonString(id),
    'name': const JsonString('Hello'),
    'type': const JsonString('query'),
    'body': JsonString(body),
  });

  group('TrustedDocuments', () {
    test('gives the text of a trusted id', () {
      expect(TrustedDocuments({hash: text}).textOf(hash), text);
    });

    test('gives null for an id it does not hold', () {
      expect(TrustedDocuments({hash: text}).textOf('0' * 64), isNull);
    });

    test('refuses an id that is not the hash of its text', () {
      expect(
        () => TrustedDocuments({hash: '{ hello }'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('decodes the manifest of typed_graphql_codegen', () {
      final result = TrustedDocuments.decode(manifest([entry(hash, text)]));
      expect(
        switch (result) {
          DecodeSuccess(:final value) => value.textOf(hash),
          DecodeFailure() => null,
        },
        text,
      );
    });

    test('decodes an entry whose id is not its hash as a failure', () {
      expect(
        TrustedDocuments.decode(manifest([entry('0' * 64, text)])),
        const DecodeFailure(
          'expected the SHA-256 of the body',
          path: [PathKey('operations'), PathIndex(0), PathKey('id')],
        ),
      );
    });

    test('decodes an entry without a body as a failure', () {
      expect(
        TrustedDocuments.decode(
          manifest([
            JsonObject({'id': JsonString(hash)}),
          ]),
        ),
        const DecodeFailure(
          'expected an object with a string id and body',
          path: [PathKey('operations'), PathIndex(0)],
        ),
      );
    });

    test('decodes another format as a failure', () {
      expect(
        TrustedDocuments.decode(
          JsonObject({...manifest([]).fields, 'format': const JsonString('x')}),
        ),
        const DecodeFailure(
          'expected "apollo-persisted-query-manifest"',
          path: [PathKey('format')],
        ),
      );
    });

    test('decodes another version as a failure', () {
      expect(
        TrustedDocuments.decode(
          JsonObject({...manifest([]).fields, 'version': JsonNumber(2)}),
        ),
        const DecodeFailure('expected 1', path: [PathKey('version')]),
      );
    });

    test('decodes a manifest without operations as a failure', () {
      expect(
        TrustedDocuments.decode(
          JsonObject({
            'format': const JsonString('apollo-persisted-query-manifest'),
            'version': JsonNumber(1),
          }),
        ),
        const DecodeFailure(
          'expected an array',
          path: [PathKey('operations')],
        ),
      );
    });

    test('decodes a value that is not an object as a failure', () {
      expect(
        TrustedDocuments.decode(const JsonString('manifest')),
        const DecodeFailure('expected an object'),
      );
    });
  });

  group('a server with trusted documents', () {
    GraphQLServer<Ctx> server() =>
        fixture.server(trustedDocuments: TrustedDocuments({hash: text}));

    test('runs a trusted hash alone', () async {
      final response = await server().handle(
        fixture.request(null, extensions: fixture.persisted(hash)),
      );
      expect(fixture.json(response), {
        'data': {'hello': 'world'},
      });
    });

    test('runs a trusted text without a hash', () async {
      final response = await server().handle(fixture.request(text));
      expect(response.outcome, ServerOutcome.executed);
    });

    test('runs a trusted text with its hash', () async {
      final response = await server().handle(
        fixture.request(text, extensions: fixture.persisted(hash)),
      );
      expect(response.outcome, ServerOutcome.executed);
    });

    test('refuses an unknown hash', () async {
      final unknown = '0' * 64;
      final response = await server().handle(
        fixture.request(null, extensions: fixture.persisted(unknown)),
      );
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL415', 'No trusted document has the id "$unknown".'),
      );
    });

    test('refuses a text that is not trusted', () async {
      final response = await server().handle(fixture.request('{ greet }'));
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL414', 'Only trusted documents are allowed.'),
      );
    });

    test('refuses a trusted text sent with another hash', () async {
      final response = await server().handle(
        fixture.request(
          text,
          extensions: fixture.persisted(fixture.hashOf('{ greet }')),
        ),
      );
      expect(fixture.codeOf(response), 'GQL411');
    });

    test('refuses a malformed extension', () async {
      final response = await server().handle(
        fixture.request(
          text,
          extensions: JsonObject({'persistedQuery': const JsonString('x')}),
        ),
      );
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL413', 'Invalid persisted query: it must be an object.'),
      );
    });

    test('reports a request with no text and no hash as GQL400', () async {
      final response = await server().handle(fixture.request(null));
      expect(fixture.codeOf(response), 'GQL400');
    });
  });

  test('a server with a store and trusted documents is refused', () {
    expect(
      () => fixture.server(
        persistedQueries: MemoryPersistedQueryStore(),
        trustedDocuments: TrustedDocuments({hash: text}),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
