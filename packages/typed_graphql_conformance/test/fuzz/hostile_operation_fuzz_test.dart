@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'hostile_rules.dart';
import 'random_executable.dart';
import 'random_operation.dart';
import 'random_parts.dart';
import 'random_valid_schema.dart';

/// R0.3, R10.3 and R10.4: random and mutated executable documents, with
/// every rule on, never throw, end, and give at most `maxErrors + 1`
/// diagnostics (the `GQL000` sink limit), each with a code.
void main() {
  final budget = FuzzBudget(defaultIterations: 300);
  const parser = Parser(options: ParserOptions(maxTokens: null));
  final tokenPattern = RegExp(r'\.\.\.|\$?[A-Za-z_]\w*|"[^"]*"|-?\d\S*|\S');
  const printer = Printer();

  String randomDocument(Random random) {
    final executable = RandomExecutable(RandomParts(random));
    return printer.print(
      Document([
        executable.operation(isFirst: true),
        for (var i = 0, n = random.nextInt(3); i < n; i++)
          executable.fragment(),
      ]),
    );
  }

  List<String> tokensOf(String text) => [
    for (final match in tokenPattern.allMatches(text)) match[0] ?? '',
  ];

  /// [text] with up to three tokens dropped, doubled or exchanged, or its
  /// tail replaced by a tail of [other].
  String mutate(Random random, String text, String other) {
    var tokens = tokensOf(text);
    for (var step = random.nextInt(4); step > 0 && tokens.isNotEmpty; step--) {
      final index = random.nextInt(tokens.length);
      switch (random.nextInt(4)) {
        case 0:
          tokens.removeAt(index);
        case 1:
          tokens.insert(index, tokens[index]);
        case 2:
          final second = random.nextInt(tokens.length);
          final kept = tokens[index];
          tokens[index] = tokens[second];
          tokens[second] = kept;
        default:
          final others = tokensOf(other);
          tokens = [
            ...tokens.take(index),
            ...others.skip(random.nextInt(others.length + 1)),
          ];
      }
    }
    return tokens.join(' ');
  }

  var outcomes = <String, int>{};

  void count(String outcome) =>
      outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;

  void check(ValidSchema schema, String text, String reason) {
    final source = Source(text);
    final document = switch (parser.parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure() => null,
    };
    if (document == null) {
      count('parse failure');
      return;
    }
    final result = HostileRules.validator.validate(
      schema,
      document,
      source: source,
    );
    count(result is ValidDocument ? 'valid' : 'invalid');
    expect(
      result.diagnostics.length,
      lessThanOrEqualTo(HostileRules.maxErrors + 1),
      reason: reason,
    );
    for (final diagnostic in result.diagnostics) {
      expect(diagnostic.code.id, startsWith('GQL'), reason: reason);
    }
  }

  test(
    'random and mutated documents never throw and report a bounded list',
    () {
      outcomes = {};
      for (var index = 0; index < budget.iterations; index++) {
        final random = budget.randomFor(index);
        final (:sdl, :schema) = RandomValidSchema(random).build();
        final valid = printer.print(
          RandomOperation(schema.schema, random).document(),
        );
        final other = printer.print(
          RandomOperation(schema.schema, random).document(),
        );
        final texts = [
          randomDocument(random),
          valid,
          mutate(random, valid, other),
          mutate(random, valid, randomDocument(random)),
          mutate(random, randomDocument(random), valid),
        ];
        for (final text in texts) {
          check(schema, text, '${budget.replay(index)}\n$sdl\n$text');
        }
      }
      if (budget.iterations >= 100) {
        expect(outcomes['valid'], greaterThan(0));
        expect(outcomes['invalid'], greaterThan(0));
        expect(outcomes['parse failure'], greaterThan(0));
      }
    },
  );
}
