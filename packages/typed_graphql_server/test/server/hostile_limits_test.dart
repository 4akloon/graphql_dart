import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hostile_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  final hostile = HostileFixture();
  final server = hostile.server();

  setUp(() {
    hostile
      ..built = 0
      ..resolved = 0;
  });

  Future<void> expectRefused(
    String text,
    String code, {
    JsonObject? variables,
  }) async {
    final response = await server.handle(
      fixture.request(text, variables: variables),
    );
    expect(fixture.codeOf(response), code);
    expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    expect(hostile.built, 0, reason: 'no context');
    expect(hostile.resolved, 0, reason: 'no resolver');
  }

  group('in production a document over a limit', () {
    test('16 levels deep is GQL232', () async {
      await expectRefused(fixture.nested(15), 'GQL232');
    });

    test('with 16 aliases is GQL233', () async {
      await expectRefused(hostile.aliases(16), 'GQL233');
    });

    test('with 51 directives is GQL234', () async {
      await expectRefused(hostile.directives(51), 'GQL234');
    });

    test('costing more than the maximum by literal is GQL238', () async {
      await expectRefused('{ items(first: 10000) { name } }', 'GQL238');
    });

    test('costing more than the maximum by variable is GQL238', () async {
      await expectRefused(
        r'query ($n: Int) { items(first: $n) { name } }',
        'GQL238',
        variables: JsonObject({'n': JsonNumber(1000000)}),
      );
    });

    test('of 100001 characters is GQL401', () async {
      await expectRefused('{ hello }'.padRight(100001), 'GQL401');
    });

    test('of 15001 tokens within the length is GQL006', () async {
      final text = '{ ${List.filled(15000, 'a').join(' ')} }';
      expect(text.length, lessThan(100000));
      await expectRefused(text, 'GQL006');
    });
  });

  group('in production a document within the limits', () {
    test('15 levels deep is served', () async {
      final response = await server.handle(fixture.request(fixture.nested(14)));
      expect(fixture.json(response)['data'], isNotNull);
      expect(hostile.built, 1);
    });

    test('with 15 aliases is served', () async {
      final response = await server.handle(
        fixture.request(hostile.aliases(15)),
      );
      expect(fixture.json(response)['data'], isNotNull);
    });
  });

  group('a fragment fan-out document', () {
    test('is costed and served within two seconds', () async {
      final text = hostile.fanOut(30);
      final watch = Stopwatch()..start();
      final response = await server.handle(fixture.request(text));
      watch.stop();
      printOnFailure('fan-out of 30 fragments took ${watch.elapsed}');
      expect(
        (response as SingleResponse).outcome,
        isNot(ServerOutcome.internalError),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });
}
