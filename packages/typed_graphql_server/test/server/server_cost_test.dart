import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/cost_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final costs = CostFixture();
  final fixture = ServerFixture();
  var built = 0;

  GraphQLServer<Ctx> serverWith(
    double? maxCost, {
    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
  }) => costs.server(maxCost, (_) {
    built++;
    return const Ctx('x');
  }, validationRules: validationRules);

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
    test('over the limit is GQL238', () async {
      final response = await send(10, '{ items(first: 10) { name } }');
      expect(fixture.codeOf(response), 'GQL238');
    });

    test('over the limit has the core rule message', () async {
      final response = await send(10, '{ items(first: 10) { name } }');
      expect(
        fixture.messageOf(response),
        'The anonymous operation has a field cost of 1 and a type cost of 11, '
        'more than the maximum of 10.',
      );
    });

    test('over the limit is a request error', () async {
      final response = await send(10, '{ items(first: 10) { name } }');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    });

    test('over the limit points at the operation', () async {
      final response = await send(
        10,
        '\n  query Q { items(first: 10) { name } }',
      );
      final errors = fixture.json(response)['errors']! as List<Object?>;
      expect((errors.first! as Map<String, Object?>)['locations'], [
        {'line': 2, 'column': 3},
      ]);
    });

    test('names a named operation', () async {
      final response = await send(10, 'query Q { items(first: 10) { name } }');
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

  test('the message is the one MaxCostRule reports', () async {
    const text = 'query Q { items(first: 10) { name } }';
    final source = Source(text);
    final document = const Parser().parse(source).requireDocument();
    final result = const DocumentValidator(
      rules: [MaxCostRule(maxCost: 10)],
    ).validate(costs.schema.schema, document, source: source);
    final response = await send(10, text);
    expect(
      fixture.messageOf(response),
      (result as InvalidDocument).diagnostics.single.message,
    );
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

    test('is costed again for a cached document', () async {
      final server = serverWith(10);
      await server.handle(
        fixture.request(text, variables: JsonObject({'n': JsonNumber(1)})),
      );
      final response = await server.handle(
        fixture.request(
          text,
          variables: JsonObject({'n': JsonNumber(1000000)}),
        ),
      );
      expect(fixture.codeOf(response), 'GQL238');
    });
  });

  group('a variable value that names no size counts as not given', () {
    // Not given, `items` has the default list size, 10: a type cost of 11.
    const text = r'query ($n: Int) { items(first: $n) { name } }';

    for (final (label, value) in <(String, JsonValue)>[
      ('a string', const JsonString('many')),
      ('a negative number', JsonNumber(-5)),
      ('null', const JsonNull()),
      ('an object', JsonObject({})),
    ]) {
      test(label, () async {
        final response = await send(
          10,
          text,
          variables: JsonObject({'n': value}),
        );
        expect(fixture.codeOf(response), 'GQL238');
      });
    }

    test('a missing value', () async {
      final response = await send(10, text);
      expect(fixture.codeOf(response), 'GQL238');
    });
  });

  test('a huge variable value is refused', () async {
    final response = await send(
      10,
      r'query ($n: Int) { items(first: $n) { name } }',
      variables: JsonObject({'n': JsonNumber(1e300)}),
    );
    expect(fixture.codeOf(response), 'GQL238');
  });

  test('a fractional variable value is left to coercion', () async {
    // 1.5 is within the limit; the executor refuses it as an Int.
    final response = await send(
      10,
      r'query ($n: Int) { items(first: $n) { name } }',
      variables: JsonObject({'n': JsonNumber(1.5)}),
    );
    expect(fixture.codeOf(response), isNot('GQL238'));
  });

  test('the operation named by operationName is costed', () async {
    final response = await send(
      10,
      'query Cheap { items(first: 1) { name } } '
      'query Costly { items(first: 10) { name } }',
      operationName: 'Costly',
    );
    expect(fixture.codeOf(response), 'GQL238');
  });

  test('of two operations sharing a name the executed one is costed', () async {
    // Without UniqueOperationNames the executor runs the last one.
    final response = await serverWith(10, validationRules: const []).handle(
      fixture.request(
        'query Q { items(first: 1) { name } } '
        'query Q { items(first: 10) { name } }',
        operationName: 'Q',
      ),
    );
    expect(fixture.codeOf(response), 'GQL238');
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
    expect(fixture.codeOf(response), 'GQL320');
  });
}
