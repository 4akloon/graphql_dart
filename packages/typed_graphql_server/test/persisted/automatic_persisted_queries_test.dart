import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/failing_store.dart';

void main() {
  final fixture = ServerFixture();
  const text = '{ hello }';
  final hash = fixture.hashOf(text);

  group('with a store', () {
    test('runs a hash alone once its text was registered', () async {
      final server = fixture.server(
        persistedQueries: MemoryPersistedQueryStore(),
      );
      await server.handle(
        fixture.request(text, extensions: fixture.persisted(hash)),
      );
      final response = await server.handle(
        fixture.request(null, extensions: fixture.persisted(hash)),
      );
      expect(fixture.json(response), {
        'data': {'hello': 'world'},
      });
    });

    test('takes an empty query with a hash as the hash alone', () async {
      final store = MemoryPersistedQueryStore()..write(hash, text);
      final response = await fixture
          .server(persistedQueries: store)
          .handle(fixture.request('', extensions: fixture.persisted(hash)));
      expect(response.outcome, ServerOutcome.executed);
    });

    test('reports an unknown hash as PersistedQueryNotFound', () async {
      final response = await fixture
          .server(persistedQueries: MemoryPersistedQueryStore())
          .handle(fixture.request(null, extensions: fixture.persisted(hash)));
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL410', 'PersistedQueryNotFound'),
      );
    });

    test('refuses a text whose hash differs', () async {
      final response = await fixture
          .server(persistedQueries: MemoryPersistedQueryStore())
          .handle(
            fixture.request('{ greet }', extensions: fixture.persisted(hash)),
          );
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL411', 'provided sha does not match query'),
      );
    });

    test('stores no text whose hash differs', () async {
      final store = MemoryPersistedQueryStore();
      await fixture
          .server(persistedQueries: store)
          .handle(
            fixture.request('{ greet }', extensions: fixture.persisted(hash)),
          );
      expect(store.length, 0);
    });

    test('stores no text that fails validation', () async {
      const invalid = '{ missing }';
      final store = MemoryPersistedQueryStore();
      await fixture
          .server(persistedQueries: store)
          .handle(
            fixture.request(
              invalid,
              extensions: fixture.persisted(fixture.hashOf(invalid)),
            ),
          );
      expect(store.length, 0);
    });

    test('runs a request without the extension as usual', () async {
      final response = await fixture
          .server(persistedQueries: MemoryPersistedQueryStore())
          .handle(fixture.request(text));
      expect(response.outcome, ServerOutcome.executed);
    });

    test('takes a JSON null extension as no persisted query', () async {
      final response = await fixture
          .server(persistedQueries: MemoryPersistedQueryStore())
          .handle(
            fixture.request(
              text,
              extensions: JsonObject({'persistedQuery': const JsonNull()}),
            ),
          );
      expect(response.outcome, ServerOutcome.executed);
    });

    test('refuses a stored text past the length limit', () async {
      final store = MemoryPersistedQueryStore()..write(hash, text);
      final profile = ServerProfile.development.withLimits(
        const ServerLimits(maxDocumentLength: 4),
      );
      final response = await fixture
          .server(profile: profile, persistedQueries: store)
          .handle(fixture.request(null, extensions: fixture.persisted(hash)));
      expect(fixture.codeOf(response), 'GQL401');
    });

    test('reports a store failure as an unexpected error', () async {
      final response = await fixture
          .server(persistedQueries: const FailingStore())
          .handle(fixture.request(null, extensions: fixture.persisted(hash)));
      expect(fixture.codeOf(response), 'GQL330');
    });
  });

  group('without a store', () {
    test('refuses a hash alone as PersistedQueryNotSupported', () async {
      final response = await fixture.server().handle(
        fixture.request(null, extensions: fixture.persisted(hash)),
      );
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL412', 'PersistedQueryNotSupported'),
      );
    });

    test('runs a text and ignores its hash', () async {
      final response = await fixture.server().handle(
        fixture.request(text, extensions: fixture.persisted(hash)),
      );
      expect(response.outcome, ServerOutcome.executed);
    });
  });
}
