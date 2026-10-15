import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/cost_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final costs = CostFixture();
  final fixture = ServerFixture();
  var built = 0;

  GraphQLServer<Ctx> serverWith(double? maxCost) => costs.server(maxCost, (_) {
    built++;
    return const Ctx('x');
  });

  Future<ServerResponse> send(
    double? maxCost,
    String query, {
    String method = 'POST',
    String? operationName,
    JsonObject? variables,
  }) => serverWith(maxCost).handle(
    fixture.request(
      query,
      method: method,
      operationName: operationName,
      variables: variables,
    ),
  );

  setUp(() => built = 0);

  group('a literal size', () {
    test('over the limit is GQL238 with the core rule message', () async {
      final response = await send(10, '{ items(first: 10) { name } }');
      expect(fixture.codeOf(response), 'GQL238');
      expect(
        fixture.messageOf(response),
        'The anonymous operation has a field cost of 1 and a type cost of 11, '
        'more than the maximum of 10.',
      );
    });

    test('is a request error pointing at a named operation', () async {
      final response = await send(
        10,
        '\n  query Q { items(first: 10) { name } }',
      );
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      final errors = fixture.json(response)['errors']! as List<Object?>;
      expect((errors.first! as Map<String, Object?>)['locations'], [
        {'line': 2, 'column': 3},
      ]);
      expect(
        fixture.messageOf(response),
        startsWith('The operation "Q" has a field cost of 1'),
      );
    });

    test('is refused before the context factory runs', () async {
      await send(10, '{ items(first: 10) { name } }');
      expect(built, 0);
    });

    test('exactly at the limit passes', () async {
      final response = await send(10, '{ items(first: 9) { name } }');
      expect(fixture.json(response)['data'], isNotNull);
    });
  });

  group('a size given by a variable', () {
    const text = r'query ($n: Int) { items(first: $n) { name } }';

    test('over the limit is refused', () async {
      final response = await send(
        10,
        text,
        variables: JsonObject({'n': JsonNumber(1000000)}),
      );
      expect(fixture.codeOf(response), 'GQL238');
    });

    test('under the limit passes for the same document', () async {
      final response = await send(
        10,
        text,
        variables: JsonObject({'n': JsonNumber(1)}),
      );
      expect(fixture.json(response)['data'], isNotNull);
    });
  });

  group('a hostile variable value', () {
    const text = r'query ($n: Int) { items(first: $n) { name } }';

    for (final (label, value) in <(String, JsonValue)>[
      ('a string', const JsonString('many')),
      ('a fraction', JsonNumber(1.5)),
      ('a negative number', JsonNumber(-5)),
      ('a huge number', JsonNumber(1e300)),
      ('null', const JsonNull()),
      ('an object', JsonObject({})),
    ]) {
      test('$label is never an internal error', () async {
        final response = await send(
          10,
          text,
          variables: JsonObject({'n': value}),
        );
        expect(
          (response as SingleResponse).outcome,
          isNot(ServerOutcome.internalError),
        );
      });
    }
  });

  test('a GET query is costed', () async {
    final response = await send(
      10,
      '{ items(first: 10) { name } }',
      method: 'GET',
    );
    expect(fixture.codeOf(response), 'GQL238');
  });

  test('no limit never refuses', () async {
    final response = await send(null, '{ items(first: 100000) { name } }');
    expect(fixture.json(response)['data'], isNotNull);
  });

  test('a request selecting no operation is left to the executor', () async {
    final response = await send(
      10,
      '{ items(first: 10) { name } }',
      operationName: 'Nope',
    );
    expect(fixture.codeOf(response), isNot('GQL238'));
  });
}
