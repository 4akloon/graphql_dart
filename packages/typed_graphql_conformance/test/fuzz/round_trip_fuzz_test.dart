@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/node_samples.dart';
import 'fuzz_budget.dart';
import 'random_executable.dart';
import 'random_parts.dart';
import 'random_type_system.dart';

/// R10.4, property 1: a random valid tree, printed and parsed again, is
/// equivalent to itself, in the canonical and in the minified form.
void main() {
  final budget = FuzzBudget(defaultIterations: 1000);
  const parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true, maxTokens: null),
  );

  Document randomDocument(RandomParts parts) {
    final executable = RandomExecutable(parts);
    final typeSystem = RandomTypeSystem(parts);
    Definition definition(int index) => switch (parts.random.nextInt(4)) {
      0 => executable.operation(isFirst: index == 0),
      1 => executable.fragment(),
      2 => typeSystem.definition(),
      _ => typeSystem.extension(),
    };
    return Document(
      List.generate(1 + parts.random.nextInt(4), definition),
    );
  }

  SchemaCoordinate randomCoordinate(RandomParts parts) =>
      switch (parts.random.nextInt(5)) {
        0 => TypeCoordinate(parts.name()),
        1 => MemberCoordinate(parts.name(), parts.name()),
        2 => ArgumentCoordinate(parts.name(), parts.name(), parts.name()),
        3 => DirectiveCoordinate(parts.name()),
        _ => DirectiveArgumentCoordinate(parts.name(), parts.name()),
      };

  void expectRoundTrip(Document document, Printer printer, int index) {
    final text = printer.print(document);
    final reason = '${budget.replay(index)}\n$text';
    switch (parser.parse(Source(text))) {
      case ParseSuccess(document: final parsed):
        expect(parsed.isEquivalentTo(document), isTrue, reason: reason);
      case ParseFailure(:final diagnostics):
        fail('$reason\n$diagnostics');
    }
  }

  test('print then parse gives an equivalent tree, canonical and minified', () {
    for (var index = 0; index < budget.iterations; index++) {
      final document = randomDocument(RandomParts(budget.randomFor(index)));
      expectRoundTrip(document, const Printer(), index);
      expectRoundTrip(document, const Printer(isMinified: true), index);
    }
  });

  test('print then parse gives an equivalent schema coordinate', () {
    for (var index = 0; index < budget.iterations; index++) {
      final coordinate = randomCoordinate(
        RandomParts(budget.randomFor(index)),
      );
      final text = const Printer().print(coordinate);
      final reason = '${budget.replay(index)}\n$text';
      switch (parser.parseSchemaCoordinate(Source(text))) {
        case ParseElementSuccess(value: final parsed):
          expect(parsed.isEquivalentTo(coordinate), isTrue, reason: reason);
        case ParseElementFailure(:final diagnostics):
          fail('$reason\n$diagnostics');
      }
    }
  });

  test('the generators build every kind of node', () {
    final kinds = <String>{};
    for (var index = 0; index < 200; index++) {
      final parts = RandomParts(budget.randomFor(index));
      kinds
        ..addAll(const NodeSamples().kindsIn(randomDocument(parts)))
        ..addAll(const NodeSamples().kindsIn(randomCoordinate(parts)));
    }
    expect(kinds, const NodeSamples().byKind().keys.toSet());
  });
}
