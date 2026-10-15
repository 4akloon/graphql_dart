import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/failing_store.dart';

// Automatic persisted queries under attack (R5.4, R5.14): a client must not
// make a hash serve another text, fill the store without bound, or reach
// validation with a hash the store does not hold.
void main() {
  final fixture = ServerFixture();
  const text = '{ hello }';
  final hash = fixture.hashOf(text);

  test('a text registered under another hash is never served', () async {
    final store = MemoryPersistedQueryStore();
    final server = fixture.server(persistedQueries: store);
    await server.handle(
      fixture.request('{ greet }', extensions: fixture.persisted(hash)),
    );
    final response = await server.handle(
      fixture.request(null, extensions: fixture.persisted(hash)),
    );
    expect(fixture.codeOf(response), 'GQL410');
  });

  test('a poisoned store entry is not run', () async {
    final store = MemoryPersistedQueryStore()..write(hash, '{ greet }');
    final response = await fixture
        .server(persistedQueries: store)
        .handle(fixture.request(null, extensions: fixture.persisted(hash)));
    expect(fixture.codeOf(response), 'GQL410');
  });

  test('a text with a syntax error is never stored', () async {
    const broken = '{ hello';
    final store = MemoryPersistedQueryStore();
    await fixture
        .server(persistedQueries: store)
        .handle(
          fixture.request(
            broken,
            extensions: fixture.persisted(fixture.hashOf(broken)),
          ),
        );
    expect(store.length, 0);
  });

  test('3000 registered texts keep the store at its capacity', () async {
    final store = MemoryPersistedQueryStore(capacity: 100);
    final server = fixture.server(persistedQueries: store);
    for (var index = 0; index < 3000; index++) {
      final query = '{ hello } # $index';
      await server.handle(
        fixture.request(
          query,
          extensions: fixture.persisted(fixture.hashOf(query)),
        ),
      );
    }
    expect(store.length, 100);
  });

  test('an unknown hash never reaches validation', () async {
    final rule = CountingRule();
    await fixture
        .server(
          persistedQueries: MemoryPersistedQueryStore(),
          validationRules: [rule, ...DocumentValidator.specifiedRules],
        )
        .handle(fixture.request(null, extensions: fixture.persisted(hash)));
    expect(rule.runs, 0);
  });

  test('a store failure is masked in production', () async {
    final response = await fixture
        .server(
          profile: ServerProfile.production,
          persistedQueries: const FailingStore(),
        )
        .handle(fixture.request(null, extensions: fixture.persisted(hash)));
    expect(fixture.messageOf(response), isNot(contains('store is down')));
    expect(fixture.codeOf(response), 'GQL330');
    expect(response.outcome, ServerOutcome.internalError);
  });

  test('a store write failure is masked in production', () async {
    final response = await fixture
        .server(
          profile: ServerProfile.production,
          persistedQueries: const WriteFailingStore(),
        )
        .handle(fixture.request(text, extensions: fixture.persisted(hash)));
    expect(fixture.codeOf(response), 'GQL330');
    expect(response.outcome, ServerOutcome.internalError);
    expect(fixture.messageOf(response), 'Unexpected error.');
  });

  test('a store write failure shows its error in development', () async {
    final response = await fixture
        .server(persistedQueries: const WriteFailingStore())
        .handle(fixture.request(text, extensions: fixture.persisted(hash)));
    expect(response.outcome, ServerOutcome.internalError);
    expect(fixture.messageOf(response), contains('store is down'));
  });

  test('a store write failure reaches the error hook', () async {
    final seen = <Object>[];
    await fixture
        .server(
          persistedQueries: const WriteFailingStore(),
          onError: (error, stackTrace, reported) {
            seen.add(error);
            return null;
          },
        )
        .handle(fixture.request(text, extensions: fixture.persisted(hash)));
    expect(seen, hasLength(1));
  });

  group('a malformed extension is GQL413:', () {
    final cases = <String, JsonValue>{
      'a string': const JsonString('x'),
      'an array': JsonArray(const []),
      'version 2': JsonObject({
        'version': JsonNumber(2),
        'sha256Hash': JsonString(hash),
      }),
      'version as a string': JsonObject({
        'version': const JsonString('1'),
        'sha256Hash': JsonString(hash),
      }),
      'no version': JsonObject({'sha256Hash': JsonString(hash)}),
      'an upper-case hash': JsonObject({
        'version': JsonNumber(1),
        'sha256Hash': JsonString(hash.toUpperCase()),
      }),
      'a short hash': JsonObject({
        'version': JsonNumber(1),
        'sha256Hash': JsonString(hash.substring(1)),
      }),
      'a long hash': JsonObject({
        'version': JsonNumber(1),
        'sha256Hash': JsonString('${hash}0'),
      }),
      'a numeric hash': JsonObject({
        'version': JsonNumber(1),
        'sha256Hash': JsonNumber(1),
      }),
      'no hash': JsonObject({'version': JsonNumber(1)}),
    };
    for (final MapEntry(key: label, value: extension) in cases.entries) {
      test(label, () async {
        final response = await fixture
            .server(persistedQueries: MemoryPersistedQueryStore())
            .handle(
              fixture.request(
                text,
                extensions: JsonObject({'persistedQuery': extension}),
              ),
            );
        expect(fixture.codeOf(response), 'GQL413');
      });
    }
  });
}
