import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hostile_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  final hostile = HostileFixture();

  /// A server whose only rule counts the validations that reach it.
  (GraphQLServer<Ctx>, CountingRule) countedServer(int cacheSize) {
    final rule = CountingRule();
    final server = hostile.server(
      profile: ServerProfile.development,
      validationRules: [rule, ...DocumentValidator.specifiedRules],
      documentCacheSize: cacheSize,
    );
    return (server, rule);
  }

  test('3000 distinct texts keep the cache at its capacity', () async {
    final (server, rule) = countedServer(100);
    for (var index = 0; index < 3000; index++) {
      await server.handle(fixture.request('{ hello } # $index'));
    }
    expect(rule.runs, 3000);

    await server.handle(fixture.request('{ hello } # 2999'));
    await server.handle(fixture.request('{ hello } # 2900'));
    expect(rule.runs, 3000, reason: 'the 100 latest are still cached');

    await server.handle(fixture.request('{ hello } # 2899'));
    expect(rule.runs, 3001, reason: 'the 101st latest was evicted');
  });

  test('the first of 3000 texts is validated again', () async {
    final (server, rule) = countedServer(100);
    for (var index = 0; index < 3000; index++) {
      await server.handle(fixture.request('{ hello } # $index'));
    }
    await server.handle(fixture.request('{ hello } # 0'));
    expect(rule.runs, 3001);
  });

  test('a failing text is validated once across repeated requests', () async {
    final (server, rule) = countedServer(100);
    for (var index = 0; index < 50; index++) {
      final response = await server.handle(fixture.request('{ nothing }'));
      expect(fixture.codeOf(response), 'GQL205');
    }
    expect(rule.runs, 1);
  });

  test('1000 requests of the same valid text validate once', () async {
    final (server, rule) = countedServer(100);
    for (var index = 0; index < 1000; index++) {
      await server.handle(fixture.request('{ hello }'));
    }
    expect(rule.runs, 1);
  });

  test('a cache of size 0 validates every request', () async {
    final (server, rule) = countedServer(0);
    for (var index = 0; index < 10; index++) {
      await server.handle(fixture.request('{ hello }'));
    }
    expect(rule.runs, 10);
  });

  test('a lone surrogate cannot poison the entry of a U+FFFD text', () async {
    // utf8.encode turns a lone surrogate into U+FFFD, so both texts hash the
    // same; the cache must key by the text itself.
    final server = hostile.server(profile: ServerProfile.development);
    final poisoned = await server.handle(
      fixture.request('{ hello } # \ud800'),
    );
    expect(fixture.json(poisoned)['errors'], isNotNull);
    final legitimate = await server.handle(
      fixture.request('{ hello } # \ufffd'),
    );
    expect(fixture.json(legitimate), {
      'data': {'hello': 'world'},
    });
  });
}
