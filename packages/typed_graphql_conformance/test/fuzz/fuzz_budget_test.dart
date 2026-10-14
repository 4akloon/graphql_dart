@TestOn('vm')
library;

import 'package:test/test.dart';

import 'fuzz_budget.dart';

void main() {
  test('uses the defaults without variables', () {
    final budget = FuzzBudget(defaultIterations: 7, environment: {});
    expect([budget.iterations, budget.seed], [7, FuzzBudget.defaultSeed]);
  });

  test('reads the iterations and the seed from the environment', () {
    final budget = FuzzBudget(
      defaultIterations: 7,
      environment: {
        'TYPED_GRAPHQL_FUZZ_ITERATIONS': '50',
        'TYPED_GRAPHQL_FUZZ_SEED': '3',
      },
    );
    expect([budget.iterations, budget.seed], [50, 3]);
  });

  for (final (name, value) in [
    ('TYPED_GRAPHQL_FUZZ_ITERATIONS', 'many'),
    ('TYPED_GRAPHQL_FUZZ_ITERATIONS', '0'),
    ('TYPED_GRAPHQL_FUZZ_SEED', '-1'),
    ('TYPED_GRAPHQL_FUZZ_SEED', ''),
  ]) {
    test('rejects $name=$value', () {
      expect(
        () => FuzzBudget(defaultIterations: 7, environment: {name: value}),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            allOf(contains(name), contains(value)),
          ),
        ),
      );
    });
  }
}
