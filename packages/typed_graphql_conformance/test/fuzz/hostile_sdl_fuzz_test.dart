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
///
/// VM only: the deep-nesting test needs the VM stack and the file reads the
/// process environment. A throw or a stack overflow ends the test without
/// the `reason` of the case, because `Error`s are not caught (as in the M2
/// hostile-text fuzzer); replay from the iteration count and seed in the
/// environment. A lowered `maxErrors` cannot be tested: `SchemaBuilder` and
/// `BuildReport` expose no limit, so the bound is the default one.
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

  /// Lexical debris a hostile text may contain: a lone surrogate, a BOM, NUL
  /// and stray punctuation the grammar rejects or reads in odd places.
  const hostilePieces = [
    '\uD800',
    '\uFEFF',
    '\u0000',
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    '@',
    '"""',
    '"',
    '...',
    '=',
    ':',
    '|',
    '&',
    '!',
    r'$',
    r'\',
    '#',
  ];

  String randomSdl(Random random) => List.generate(
    random.nextInt(30),
    (_) => pieces[random.nextInt(pieces.length)],
  ).join('\n');

  /// Few definitions that do not conflict, so most of them build.
  String mostlyValidSdl(Random random) {
    const valid = [
      'type A { a: String }',
      'type B implements A { a: String b: Int }',
      'interface I { a: String }',
      'union U = A | B',
      'enum Color { RED GREEN }',
      'input In { a: Int = 1 }',
      'scalar Date',
      'directive @tag(name: String) on FIELD',
      'extend type Query { b: Int }',
      'extend enum E { B }',
      'schema { query: A }',
    ];
    final chosen = List.of(valid)..shuffle(random);
    return chosen.take(random.nextInt(4)).join('\n');
  }

  /// [text] with two of its lines exchanged.
  String swapTwoLines(Random random, String text) {
    final lines = text.split('\n');
    final first = random.nextInt(lines.length);
    final second = random.nextInt(lines.length);
    final kept = lines[first];
    lines[first] = lines[second];
    lines[second] = kept;
    return lines.join('\n');
  }

  /// [text] with one to five cuts, copies, insertions of valid or hostile
  /// pieces, swaps of two lines or truncations.
  String mutate(Random random, String text) {
    var mutated = text;
    for (var step = random.nextInt(5); step >= 0; step--) {
      final start = random.nextInt(mutated.length + 1);
      final end = min(mutated.length, start + random.nextInt(40));
      mutated = switch (random.nextInt(6)) {
        0 => mutated.replaceRange(start, end, ''),
        1 => mutated.replaceRange(start, start, mutated.substring(start, end)),
        2 => mutated.replaceRange(
          start,
          start,
          pieces[random.nextInt(pieces.length)],
        ),
        3 => mutated.replaceRange(
          start,
          start,
          hostilePieces[random.nextInt(hostilePieces.length)],
        ),
        4 => mutated.substring(0, random.nextInt(mutated.length + 1)),
        _ => swapTwoLines(random, mutated),
      };
    }
    return mutated;
  }

  /// Outcomes of the fuzz loops only, per entry point; reset per test.
  var successes = <String, int>{};
  var failures = <String, int>{};
  var parseSuccesses = 0;

  void resetCounters() {
    successes = {'fromSdl': 0, 'extend': 0};
    failures = {'fromSdl': 0, 'extend': 0};
    parseSuccesses = 0;
  }

  /// The text itself, and its code units when it is not plain ASCII.
  String describe(String text) => text.codeUnits.every((unit) => unit < 128)
      ? text
      : '$text ${text.codeUnits}';

  /// The diagnostics of building [text] and of extending the base schema
  /// with it, each checked to be bounded and placed.
  List<Diagnostic> buildBoth(
    String text,
    String reason, {
    ParserOptions? options,
  }) {
    final source = Source(text);
    final result = Parser(
      options: options ?? const ParserOptions(allowDirectiveExtensions: true),
    ).parse(source);
    final document = switch (result) {
      ParseSuccess(:final document) => document,
      ParseFailure(:final partial) => partial,
    };
    if (result is ParseSuccess) {
      parseSuccesses++;
    }
    final results = {
      'fromSdl': builder.fromSdl(document, source: source),
      'extend': builder.extend(base, document, source: source),
    };
    for (final MapEntry(key: entryPoint, value: built) in results.entries) {
      final outcomes = built is BuildSuccess ? successes : failures;
      outcomes[entryPoint] = outcomes[entryPoint]! + 1;
      expect(
        built.diagnostics.length,
        lessThanOrEqualTo(DiagnosticSink.defaultMaxErrors + 1),
        reason: reason,
      );
      for (final diagnostic in built.diagnostics) {
        expect(diagnostic.span?.excerpt, isNotNull, reason: reason);
      }
    }
    return [for (final built in results.values) ...built.diagnostics];
  }

  test('random definitions never throw and reach every build diagnostic', () {
    resetCounters();
    final codes = <String>{};
    for (var index = 0; index < budget.iterations; index++) {
      final text = randomSdl(budget.randomFor(index));
      final reason = '${budget.replay(index)}\n${describe(text)}';
      codes.addAll([
        for (final diagnostic in buildBoth(text, reason)) diagnostic.code.id,
      ]);
    }
    // With a handful of iterations the pieces cannot be expected to cover
    // every code, so the coverage check needs a real budget.
    if (budget.iterations >= 200) {
      expect(codes, {
        for (var id = 100; id <= 110; id++) 'GQL$id',
      });
    }
  });

  test('mutated definitions never throw and report a bounded list', () {
    resetCounters();
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final text = mutate(random, randomSdl(random));
      buildBoth(text, '${budget.replay(index)}: ${describe(text)}');
    }
  });

  test('both entry points build some texts and fail on others', () {
    resetCounters();
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final text = switch (index % 3) {
        0 => mostlyValidSdl(random),
        1 => mutate(random, mostlyValidSdl(random)),
        _ => randomSdl(random),
      };
      buildBoth(text, '${budget.replay(index)}: ${describe(text)}');
    }
    // A third of the texts have at most three of eleven valid definitions
    // that cannot conflict, and `fromSdl` and `extend` accept all of them
    // except the empty-text and `schema` corners, so a quarter is a floor
    // that holds in practice; a tiny budget has no floor.
    final floor = budget.iterations < 20 ? 0 : budget.iterations ~/ 4;
    for (final entryPoint in successes.keys) {
      expect(
        successes[entryPoint],
        greaterThanOrEqualTo(floor),
        reason: entryPoint,
      );
      expect(failures[entryPoint], greaterThan(0), reason: entryPoint);
    }
    expect(parseSuccesses, greaterThanOrEqualTo(floor));
  });

  test('deep nesting past the parser limit is a parse diagnostic', () {
    resetCounters();
    const depth = 5000;
    final text = 'type A { a(x: [Int] = ${'[' * depth}${']' * depth}): Int }';
    final result = const Parser().parse(Source(text));
    expect(result, isA<ParseFailure>());
    expect(result.diagnostics, isNotEmpty);
    buildBoth(text, 'default parser');
  });

  // The parser recurses too: with a raised `maxDepth` it overflowed the VM
  // stack inside this test at object nesting of 990 (the lists survive past
  // 1 100), so objects stay at 500, far from the limit of any stack size.
  test('deep trees that parse build without throwing', () {
    resetCounters();
    const justUnder = JsonReader.maxSupportedDepth - 10;
    const objectDepth = 500;
    for (final depth in [justUnder, JsonReader.maxSupportedDepth + 100]) {
      final listType = '${'[' * depth}Int${']' * depth}';
      final listValue = '${'[' * depth}${']' * depth}';
      final objectValue = '${'{a: ' * objectDepth}1${'}' * objectDepth}';
      for (final text in [
        'type A { a: $listType }',
        'type A { a(x: [Int] = $listValue): Int }',
        'input I { a: Int = $objectValue }',
        'directive @d(a: Int = $listValue) on FIELD',
        'type A @d(a: $objectValue) { a: Int }',
      ]) {
        buildBoth(
          text,
          'depth $depth',
          options: ParserOptions(
            allowDirectiveExtensions: true,
            maxDepth: depth + 10,
          ),
        );
      }
    }
    expect(parseSuccesses, 10);
    expect(failures['fromSdl'], 0);
  });

  test('a deep default value builds and is refused by the converter', () {
    const depth = JsonReader.maxSupportedDepth + 100;
    final source = Source(
      'directive @d(a: [Int] = ${'[' * depth}${']' * depth}) on FIELD',
    );
    final parsed = const Parser(options: ParserOptions(maxDepth: depth + 10))
        .parse(source)
        .requireDocument();
    final built = builder.fromSdl(parsed, source: source);
    expect(built, isA<BuildSuccess>());
    final value = (built as BuildSuccess).schema
        .directiveNamed('d')!
        .arguments
        .single
        .defaultValue!;
    expect(const LiteralConverter().convert(value), isA<DecodeFailure>());
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
