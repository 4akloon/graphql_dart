@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/kitchen_sink.dart';
import 'element_corpora.dart';
import 'fuzz_budget.dart';

/// R10.4, property 2: arbitrary and mutated text never throws, ends, and
/// gives at most `maxErrors + 1` diagnostics, each at a place an excerpt
/// can show, from every parser entry point.
void main() {
  final budget = FuzzBudget(defaultIterations: 1000);
  // The kitchen sink SDL uses directive extensions.
  const parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true),
  );

  /// Pieces of text the lexer and the parser treat specially, and some
  /// they reject: a lone surrogate, NUL, a single quote.
  const pieces = [
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    '!',
    r'$',
    '&',
    '|',
    '@',
    ':',
    '=',
    '.',
    '...',
    '"',
    '"""',
    r'\',
    r'\u',
    '#',
    '\n',
    '\r',
    '\r\n',
    ' ',
    '\t',
    ',',
    'a',
    'on',
    'query',
    'fragment',
    'type',
    'extend',
    'directive',
    '1',
    '-',
    '1.5e',
    '0x',
    '\uD800',
    '\u{1F600}',
    '\u0000',
    "'",
    '﻿',
  ];

  String randomText(Random random) => List.generate(
    random.nextInt(80),
    (_) => pieces[random.nextInt(pieces.length)],
  ).join();

  /// [seed] with one to five cuts, copies and insertions.
  String mutate(Random random, String seed) {
    var text = seed;
    for (var step = random.nextInt(5); step >= 0 && text.isNotEmpty; step--) {
      final start = random.nextInt(text.length);
      final end = min(text.length, start + random.nextInt(40));
      text = switch (random.nextInt(3)) {
        0 => text.replaceRange(start, end, ''),
        1 => text.replaceRange(start, start, text.substring(start, end)),
        _ => text.replaceRange(
          start,
          start,
          pieces[random.nextInt(pieces.length)],
        ),
      };
    }
    return text;
  }

  void expectBounded(List<Diagnostic> diagnostics, String reason) {
    expect(
      diagnostics.length,
      lessThanOrEqualTo(DiagnosticSink.defaultMaxErrors + 1),
      reason: reason,
    );
    for (final diagnostic in diagnostics) {
      expect(diagnostic.span?.excerpt, isNotNull, reason: reason);
    }
  }

  /// Every entry point with the seeds of its own grammar.
  final entryPoints =
      <(String, List<String>, List<Diagnostic> Function(Source))>[
        (
          'parse',
          [KitchenSink.query, KitchenSink.sdl],
          (s) => parser.parse(s).diagnostics,
        ),
        (
          'parseValue',
          ElementCorpora.values,
          (s) => parser.parseValue(s).diagnostics,
        ),
        (
          'parseValue const',
          ElementCorpora.constValues,
          (s) => parser.parseValue(s, isConst: true).diagnostics,
        ),
        (
          'parseTypeRef',
          ElementCorpora.types,
          (s) => parser.parseTypeRef(s).diagnostics,
        ),
        (
          'parseSchemaCoordinate',
          ElementCorpora.coordinates,
          (s) => parser.parseSchemaCoordinate(s).diagnostics,
        ),
      ];

  void expectLexerEnds(String text, String reason) {
    final sink = DiagnosticSink();
    final lexer = Lexer(Source(text), sink);
    var steps = 0;
    while (lexer.advance().kind != TokenKind.eof) {
      steps++;
      // Every token covers at least one character.
      expect(steps, lessThanOrEqualTo(text.length + 1), reason: reason);
    }
    expectBounded(sink.diagnostics, reason);
  }

  test('random text never throws and reports a bounded list', () {
    for (var index = 0; index < budget.iterations; index++) {
      final text = randomText(budget.randomFor(index));
      final reason = '${budget.replay(index)}: ${text.codeUnits}';
      for (final (_, _, run) in entryPoints) {
        expectBounded(run(Source(text)), reason);
      }
      expectLexerEnds(text, reason);
    }
  });

  test('mutated seeds never throw, and reach both outcomes', () {
    final outcomes = <String, Set<bool>>{};
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      for (final (name, seeds, run) in entryPoints) {
        final text = mutate(random, seeds[random.nextInt(seeds.length)]);
        final reason = '$name, ${budget.replay(index)}: ${text.codeUnits}';
        final diagnostics = run(Source(text));
        expectBounded(diagnostics, reason);
        outcomes.putIfAbsent(name, () => {}).add(diagnostics.isEmpty);
        expectLexerEnds(text, reason);
      }
    }
    // A fuzzer whose mutations always fail at the first token proves nothing
    // about the deeper grammar.
    for (final (name, _, _) in entryPoints) {
      expect(outcomes[name], {true, false}, reason: name);
    }
  });

  test('every unmutated seed parses cleanly', () {
    for (final (name, seeds, run) in entryPoints) {
      for (final seed in seeds) {
        expect(run(Source(seed)), isEmpty, reason: '$name: $seed');
      }
    }
  });

  test('a long hostile text reaches the sink limit and stops there', () {
    // Each NUL is a lexer error, so every unit reports one diagnostic.
    final source = Source('\u0000 ' * 5000);
    for (final (name, _, run) in entryPoints) {
      final diagnostics = run(source);
      if (name == 'parse') {
        expect(diagnostics, hasLength(DiagnosticSink.defaultMaxErrors + 1));
        expect(diagnostics.last.code, DiagnosticCode.diagnosticLimitReached);
      }
      expectBounded(diagnostics, name);
    }
    expectLexerEnds('\u0000 ' * 5000, 'lexer');
  });

  test('deeply nested input stays within the depth limit', () {
    const parser = Parser(); // default maxDepth
    const depth = 5000;
    final document = Source('{ a ' * depth);
    final value = Source('[' * depth);
    expectBounded(parser.parse(document).diagnostics, 'selections');
    expectBounded(parser.parseValue(value).diagnostics, 'lists');
    expectBounded(
      parser.parseValue(Source('{a:' * depth)).diagnostics,
      'objects',
    );
    expectBounded(parser.parseTypeRef(value).diagnostics, 'list types');
  });
}
