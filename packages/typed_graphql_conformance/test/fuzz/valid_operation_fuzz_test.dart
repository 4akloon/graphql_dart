@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'random_operation.dart';
import 'random_valid_schema.dart';

/// R0.3, R10.3 and R10.4: an operation that is valid by construction over a
/// random valid schema passes every specified rule, as printed text parsed
/// back. A failure names the case, the schema and the operation.
void main() {
  final budget = FuzzBudget(defaultIterations: 300);
  const parser = Parser(options: ParserOptions(maxTokens: null));

  test('generated operations are valid', () {
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final (:sdl, :schema) = RandomValidSchema(
        random,
        replay: budget.replay(index),
      ).build();
      for (var round = 0; round < 3; round++) {
        final text = const Printer().print(
          RandomOperation(schema.schema, random).document(),
        );
        final reason = '${budget.replay(index)}\n$sdl\n$text';
        final source = Source(text);
        final document = switch (parser.parse(source)) {
          ParseSuccess(:final document) => document,
          ParseFailure(:final diagnostics) => fail('$reason\n$diagnostics'),
        };
        final result = const DocumentValidator().validate(
          schema,
          document,
          source: source,
        );
        expect(result.diagnostics, isEmpty, reason: reason);
        expect(result, isA<ValidDocument>(), reason: reason);
      }
    }
  });

  test('the generator reaches fragments, variables and aliases', () {
    final features = <String>{};
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final schema = RandomValidSchema(
        random,
        replay: budget.replay(index),
      ).build().schema;
      final text = const Printer().print(
        RandomOperation(schema.schema, random).document(),
      );
      if (text.contains('fragment ')) features.add('fragment');
      if (text.contains('... on ')) features.add('inline fragment');
      if (text.contains(r'$')) features.add('variable');
      if (RegExp(r'\ba\d+:').hasMatch(text)) features.add('alias');
      if (text.contains('@skip') || text.contains('@include')) {
        features.add('directive');
      }
    }
    if (budget.iterations >= 100) {
      expect(features, {
        'fragment',
        'inline fragment',
        'variable',
        'alias',
        'directive',
      });
    }
  });
}
