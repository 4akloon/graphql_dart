@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';

/// R10.4 and spec §11 of M3, property 2 for SDL: hostile type-system
/// text, built or used to extend a schema, never throws, ends, and gives
/// at most `maxErrors + 1` diagnostics, each at a place an excerpt can
/// show.
void main() {
  final budget = FuzzBudget(defaultIterations: 1000);
  const parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true),
  );
  const builder = SchemaBuilder();

  /// Definitions over a few names, so that repeats, unknown targets,
  /// kind mismatches and built-in names are common.
  const pieces = [
    '"""desc""" type A { a: String }',
    'type A { a: Int a: Int }',
    'type B implements A { a(x: Int, x: Int): A }',
    'interface A { a: String }',
    'union U = A | B',
    'enum E { A B A }',
    'input I { a: Int a: Int }',
    'scalar A',
    'scalar String',
    'scalar __Schema',
    'extend type A { b: Int }',
    'extend type Query { a: Int }',
    'extend interface A @d',
    'extend union U = Query',
    'extend enum E { A }',
    'extend input I { b: Int }',
    'extend scalar B @d',
    'extend scalar String @d',
    'extend type Missing @d',
    'directive @d on FIELD',
    'directive @d(a: Int, a: Int) on FIELD',
    'directive @skip on FIELD',
    'extend directive @d @d',
    'extend directive @include @d',
    'extend directive @missing @d',
    'schema { query: A query: B }',
    'schema { mutation: B }',
    'extend schema { query: A }',
    'extend schema @d',
    'query { a }',
    'fragment F on A { a }',
  ];

  final base = switch (builder.fromSdl(
    parser
        .parse(Source('type Query { a: String } enum E { A }'))
        .requireDocument(),
  )) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => fail('$diagnostics'),
  };

  String randomSdl(Random random) => List.generate(
    random.nextInt(30),
    (_) => pieces[random.nextInt(pieces.length)],
  ).join('\n');

  /// [text] with one to five cuts, copies and insertions.
  String mutate(Random random, String text) {
    var mutated = text;
    for (var step = random.nextInt(5); step >= 0; step--) {
      final start = random.nextInt(mutated.length + 1);
      final end = min(mutated.length, start + random.nextInt(40));
      mutated = switch (random.nextInt(3)) {
        0 => mutated.replaceRange(start, end, ''),
        1 => mutated.replaceRange(start, start, mutated.substring(start, end)),
        _ => mutated.replaceRange(
          start,
          start,
          pieces[random.nextInt(pieces.length)],
        ),
      };
    }
    return mutated;
  }

  /// Per entry point, how many builds succeeded and how many failed, so
  /// that no entry point is quietly vacuous.
  final successes = <String, int>{'fromSdl': 0, 'extend': 0};
  final failures = <String, int>{'fromSdl': 0, 'extend': 0};

  /// The diagnostics of building [text] and of extending the base schema
  /// with it, each checked to be bounded and placed.
  List<Diagnostic> buildBoth(String text, String reason) {
    final source = Source(text);
    final document = switch (parser.parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure(:final partial) => partial,
    };
    final results = {
      'fromSdl': builder.fromSdl(document, source: source),
      'extend': builder.extend(base, document, source: source),
    };
    for (final MapEntry(key: entryPoint, value: result) in results.entries) {
      final outcomes = result is BuildSuccess ? successes : failures;
      outcomes[entryPoint] = outcomes[entryPoint]! + 1;
      expect(
        result.diagnostics.length,
        lessThanOrEqualTo(DiagnosticSink.defaultMaxErrors + 1),
        reason: reason,
      );
      for (final diagnostic in result.diagnostics) {
        expect(diagnostic.span?.excerpt, isNotNull, reason: reason);
      }
    }
    return [for (final result in results.values) ...result.diagnostics];
  }

  test('random definitions never throw and reach every build diagnostic', () {
    final codes = <String>{};
    for (var index = 0; index < budget.iterations; index++) {
      final text = randomSdl(budget.randomFor(index));
      final reason = '${budget.replay(index)}\n$text';
      codes.addAll([
        for (final diagnostic in buildBoth(text, reason)) diagnostic.code.id,
      ]);
    }
    expect(codes, {
      for (var id = 100; id <= 110; id++) 'GQL$id',
    });
  });

  test('mutated definitions never throw and report a bounded list', () {
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final text = mutate(random, randomSdl(random));
      buildBoth(text, '${budget.replay(index)}: ${text.codeUnits}');
    }
  });

  test('both entry points produced successes and failures', () {
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      buildBoth(
        index.isEven ? randomSdl(random) : mutate(random, randomSdl(random)),
        'entry points',
      );
    }
    // Short texts build; long ones always fail on a repeat.
    for (final text in [
      'type A { a: Int }',
      'extend type Query { b: Int }',
      'type A\ntype A',
    ]) {
      buildBoth(text, 'seed texts');
    }
    for (final entryPoint in successes.keys) {
      expect(successes[entryPoint], greaterThan(0), reason: entryPoint);
      expect(failures[entryPoint], greaterThan(0), reason: entryPoint);
    }
  });

  test('deeply nested types and values never throw or overflow', () {
    for (final depth in [100, 120, 5000, 100000]) {
      final listType = '${'[' * depth}Int${']' * depth}';
      final listValue = '${'[' * depth}${']' * depth}';
      final objectValue = '${'{a: ' * depth}1${'}' * depth}';
      for (final text in [
        'type A { a: $listType }',
        'type A { a(x: [Int] = $listValue): Int }',
        'input I { a: Int = $objectValue }',
        'directive @d(a: Int = $listValue) on FIELD',
        'type A @d(a: $objectValue) { a: Int }',
      ]) {
        buildBoth(text, 'depth $depth');
      }
    }
  });

  test('many repeated definitions reach the sink limit and stop there', () {
    final diagnostics = buildBoth('type A\n' * 300, 'repeats');
    expect(diagnostics, hasLength(2 * (DiagnosticSink.defaultMaxErrors + 1)));
    expect(diagnostics.last.code, DiagnosticCode.diagnosticLimitReached);
    expect(
      diagnostics.where((d) => d.code == DiagnosticCode.diagnosticLimitReached),
      hasLength(2),
    );
  });
}
