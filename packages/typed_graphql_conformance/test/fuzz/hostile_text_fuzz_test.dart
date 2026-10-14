@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/kitchen_sink.dart';
import 'fuzz_budget.dart';

/// R10.4, property 2: arbitrary and mutated text never throws, ends, and
/// gives at most `maxErrors + 1` diagnostics, each at a place an excerpt
/// can show, from every parser entry point.
void main() {
  final budget = FuzzBudget(defaultIterations: 1000);
  const parser = Parser();

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

  /// A kitchen sink with one to five cuts, copies and insertions.
  String mutated(Random random) {
    var text = random.nextBool() ? KitchenSink.query : KitchenSink.sdl;
    for (var step = random.nextInt(5); step >= 0; step--) {
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

  void expectWellBehaved(String text, String reason) {
    final source = Source(text);
    final runs = [
      () => parser.parse(source).diagnostics,
      () => parser.parseValue(source).diagnostics,
      () => parser.parseValue(source, isConst: true).diagnostics,
      () => parser.parseTypeRef(source).diagnostics,
      () => parser.parseSchemaCoordinate(source).diagnostics,
    ];
    for (final run in runs) {
      final diagnostics = run();
      expect(
        diagnostics.length,
        lessThanOrEqualTo(DiagnosticSink.defaultMaxErrors + 1),
        reason: reason,
      );
      for (final diagnostic in diagnostics) {
        expect(diagnostic.span?.excerpt, isNotNull, reason: reason);
      }
    }
  }

  test('random text never throws and reports a bounded list', () {
    for (var index = 0; index < budget.iterations; index++) {
      final text = randomText(budget.randomFor(index));
      expectWellBehaved(text, '${budget.replay(index)}: ${text.codeUnits}');
    }
  });

  test('mutated documents never throw and report a bounded list', () {
    for (var index = 0; index < budget.iterations; index++) {
      final text = mutated(budget.randomFor(index));
      expectWellBehaved(text, '${budget.replay(index)}: ${text.codeUnits}');
    }
  });

  test('a long hostile text stays within the sink limit', () {
    final random = budget.randomFor(0);
    final text = List.generate(
      5000,
      (_) => pieces[random.nextInt(pieces.length)],
    ).join();
    expectWellBehaved(text, 'long text of ${budget.replay(0)}');
  });
}
