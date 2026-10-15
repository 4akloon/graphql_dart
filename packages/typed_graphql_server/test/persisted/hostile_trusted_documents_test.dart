import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';

// Trusted documents under attack (R5.4): only a trusted text runs, to the
// character, and nothing a client sends reaches the parser otherwise.
void main() {
  final fixture = ServerFixture();
  const text = '{hello}';
  final hash = fixture.hashOf(text);
  final trusted = TrustedDocuments({hash: text});

  (GraphQLServer<Ctx>, CountingRule) countedServer() {
    final rule = CountingRule();
    final server = fixture.server(
      trustedDocuments: trusted,
      validationRules: [rule, ...DocumentValidator.specifiedRules],
    );
    return (server, rule);
  }

  for (final variant in ['{ hello}', '{hello}\n', '{hello} # comment']) {
    test(
      'the variant ${jsonEncode(variant)} of a trusted text is refused',
      () async {
        final response = await fixture
            .server(trustedDocuments: trusted)
            .handle(fixture.request(variant));
        expect(fixture.codeOf(response), 'GQL414');
      },
    );
  }

  test('an untrusted text never reaches validation', () async {
    final (server, rule) = countedServer();
    await server.handle(fixture.request('{ greet }'));
    expect(rule.runs, 0);
  });

  test('an untrusted text is refused before it is parsed', () async {
    final response = await fixture
        .server(trustedDocuments: trusted)
        .handle(fixture.request('{ {{{ not graphql'));
    expect(fixture.codeOf(response), 'GQL414');
  });

  test('an unknown hash never reaches validation', () async {
    final (server, rule) = countedServer();
    await server.handle(
      fixture.request(null, extensions: fixture.persisted('0' * 64)),
    );
    expect(rule.runs, 0);
  });

  test('a trusted hash cannot carry an untrusted text', () async {
    final response = await fixture
        .server(trustedDocuments: trusted)
        .handle(
          fixture.request('{ greet }', extensions: fixture.persisted(hash)),
        );
    expect(fixture.codeOf(response), 'GQL411');
  });

  test('a manifest entry naming another body is not decoded', () {
    final forged = JsonObject({
      'format': const JsonString('apollo-persisted-query-manifest'),
      'version': JsonNumber(1),
      'operations': JsonArray([
        JsonObject({
          'id': JsonString(hash),
          'body': const JsonString('mutation { bump }'),
        }),
      ]),
    });
    expect(TrustedDocuments.decode(forged), isA<DecodeFailure>());
  });

  test('a server with a store and trusted documents is refused', () {
    expect(
      () => fixture.server(
        persistedQueries: MemoryPersistedQueryStore(),
        trustedDocuments: trusted,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
