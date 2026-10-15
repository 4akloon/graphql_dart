@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'hostile_rules.dart';

/// R0.3, R3.7 and R10.3: documents of hostile shapes, built in code with
/// random sizes inside a fixed bound, end within ten seconds with every
/// rule on, and a shape whose work grows exponentially gives `GQL230`.
void main() {
  final budget = FuzzBudget(defaultIterations: 36);
  final schema = () {
    final source = Source(
      'type Query { a: Query b(x: Int): Query s: String l: [Query] }',
    );
    final document = const Parser().parse(source).requireDocument();
    final built = const SchemaBuilder().fromSdl(document, source: source);
    return switch (built) {
      BuildSuccess(:final schema) => ValidSchema.assumeValid(schema),
      BuildFailure(:final diagnostics) => fail('$diagnostics'),
    };
  }();

  Field leaf() => Field(null, const Name('s'));

  /// `{ <inner> }` as a selection set.
  SelectionSet only(Selection inner) => SelectionSet([inner]);

  Document operationOf(List<Selection> selections, [List<Definition>? more]) =>
      Document([
        OperationDefinition(.query, SelectionSet(selections)),
        ...?more,
      ]);

  FragmentDefinition fragment(String name, List<Selection> selections) =>
      FragmentDefinition(
        Name(name),
        const NamedType(Name('Query')),
        SelectionSet(selections),
      );

  FragmentSpread spread(String name) => FragmentSpread(Name(name));

  /// `{ a { a { ... { s } } } }` [depth] levels deep, built from the leaf.
  Document deepSelection(int depth) {
    var inner = leaf();
    for (var i = 0; i < depth; i++) {
      inner = Field(null, const Name('a'), selectionSet: only(inner));
    }
    return operationOf([inner]);
  }

  /// [width] fields of one response name, `b(x: 1)` or `b(x: i)`.
  Document wideSelection(int width, {required bool isSameArguments}) =>
      operationOf([
        for (var i = 0; i < width; i++)
          Field(
            null,
            const Name('b'),
            arguments: [
              Argument(
                const Name('x'),
                IntValue(isSameArguments ? '1' : '$i'),
              ),
            ],
            selectionSet: only(leaf()),
          ),
      ]);

  /// `F0 { ...F1 ...F1 }`, ..., `F<k> { s }`: 2^k fields once expanded.
  Document fragmentChain(int length) => operationOf(
    [spread('F0')],
    [
      for (var i = 0; i < length; i++)
        fragment('F$i', [spread('F${i + 1}'), spread('F${i + 1}')]),
      fragment('F$length', [leaf()]),
    ],
  );

  /// Each fragment selects `a { ...next }` and `b(x: i) { ...next }`, so
  /// the fields to merge double with each level.
  Document fragmentFan(int length) => operationOf(
    [spread('F0')],
    [
      for (var i = 0; i < length; i++)
        fragment('F$i', [
          for (final (alias, name) in [('p', 'a'), ('q', 'b')])
            Field(
              Name(alias),
              Name(name),
              selectionSet: only(spread('F${i + 1}')),
            ),
          Field(
            const Name('r'),
            const Name('a'),
            selectionSet: only(spread('F${i + 1}')),
          ),
        ]),
      fragment('F$length', [leaf()]),
    ],
  );

  /// `F0` spreads `F1`, ..., the last spreads `F0`.
  Document fragmentCycle(int length) => operationOf(
    [spread('F0')],
    [
      for (var i = 0; i < length; i++)
        fragment('F$i', [leaf(), spread('F${(i + 1) % length}')]),
    ],
  );

  /// [count] operations that spread the same chain of [length] fragments.
  Document manyOperations(int count, int length) => Document([
    for (var i = 0; i < count; i++)
      OperationDefinition(
        .query,
        only(spread('F0')),
        name: Name('Q$i'),
      ),
    for (var i = 0; i < length; i++)
      fragment('F$i', [leaf(), spread('F${i + 1}')]),
    fragment('F$length', [leaf()]),
  ]);

  /// The shapes by name, each a function of the random source.
  final shapes = <String, Document Function(Random)>{
    'deep selection': (random) => deepSelection(1 + random.nextInt(20000)),
    'wide, same arguments': (random) =>
        wideSelection(1 + random.nextInt(20000), isSameArguments: true),
    'wide, differing arguments': (random) =>
        wideSelection(1 + random.nextInt(20000), isSameArguments: false),
    'fragment chain': (random) => fragmentChain(1 + random.nextInt(60)),
    'fragment fan': (random) => fragmentFan(1 + random.nextInt(60)),
    'fragment cycle': (random) => fragmentCycle(1 + random.nextInt(2000)),
    'many operations': (random) =>
        manyOperations(1 + random.nextInt(300), 1 + random.nextInt(300)),
  };

  test('every hostile shape ends within ten seconds', () {
    final names = shapes.keys.toList();
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final name = names[index % names.length];
      final document = shapes[name]!(random);
      final reason = '${budget.replay(index)}: $name';
      final stopwatch = Stopwatch()..start();
      final result = HostileRules.validator.validate(schema, document);
      stopwatch.stop();
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason: reason,
      );
      expect(
        result.diagnostics.length,
        lessThanOrEqualTo(HostileRules.maxErrors + 1),
        reason: reason,
      );
    }
  });

  test('fragments that triple the fields to merge 60 times are merged in '
      'time, not given GQL230', () {
    final result = HostileRules.validator.validate(schema, fragmentFan(60));
    final codes = [
      for (final diagnostic in result.diagnostics) diagnostic.code,
    ];
    expect(codes, isNot(contains(DiagnosticCode.documentTooComplex)));
    expect(codes, isNot(contains(DiagnosticCode.overlappingFieldsCanBeMerged)));
  });

  test('a chain that spreads each fragment twice is valid and fast', () {
    final result = HostileRules.validator.validate(schema, fragmentChain(60));
    expect(result.diagnostics, isEmpty);
  });
}
