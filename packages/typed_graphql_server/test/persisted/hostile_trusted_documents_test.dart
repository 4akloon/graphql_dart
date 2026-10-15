import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';

// Trusted documents under attack (R5.4): only a trusted text runs, to the
// character, and nothing a client sends reaches the parser otherwise.
/// Records the source text of every document the phase accepts.
final class _SourceRecorder extends ServerExtension<Ctx> {
  const _SourceRecorder(this.seen);

  final List<String?> seen;

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) async {
    final result = await next(request);
    if (result case DocumentAccepted(:final source)) seen.add(source.body);
    return result;
  }
}

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

  test('a lone surrogate text runs the trusted text, not its own', () async {
    // Both texts hash to the same SHA-256 because utf8.encode turns a lone
    // surrogate into U+FFFD; only the manifest's text may run.
    const manifestText = '{ hello } # \ufffd';
    const forgedText = '{ hello } # \ud800';
    final server = fixture.server(
      trustedDocuments: TrustedDocuments({
        fixture.hashOf(manifestText): manifestText,
      }),
    );
    final forged = await server.handle(fixture.request(forgedText));
    final genuine = await server.handle(fixture.request(manifestText));
    expect(fixture.json(forged), fixture.json(genuine));
    expect(fixture.json(forged), {
      'data': {'hello': 'world'},
    });
  });

  test('the text that runs is the manifest text', () async {
    const manifestText = '{ hello } # \ufffd';
    final seen = <String?>[];
    final server = fixture.server(
      trustedDocuments: TrustedDocuments({
        fixture.hashOf(manifestText): manifestText,
      }),
      extensions: [_SourceRecorder(seen)],
    );
    await server.handle(fixture.request('{ hello } # \ud800'));
    expect(seen, ['{ hello } # \ufffd']);
  });
}
