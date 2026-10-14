import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text, int maxAliases) =>
      checked.errors(text, [MaxAliasesRule(maxAliases: maxAliases)]);

  test('an operation at the limit is valid', () {
    expect(errors('{ x: b y: b z: a { w: b } }', 4), isEmpty);
  });

  test('an anonymous operation one over reports', () {
    expect(errors('{ x: b y: b z: b }', 2), [
      '1:1 GQL233 The anonymous operation has more than 2 aliases.',
    ]);
  });

  test('a named operation is named in the message', () {
    expect(errors('query Q { x: b y: b }', 1), [
      '1:1 GQL233 The operation "Q" has more than 1 aliases.',
    ]);
  });

  test('a fragment counts once per spread', () {
    const text = '{ ...F ...F } fragment F on Query { x: b }';
    expect(errors(text, 2), isEmpty);
    expect(errors(text, 1), hasLength(1));
  });

  test('a fragment cycle counts its edge as 0', () {
    expect(errors('{ ...F } fragment F on Query { x: b ...F }', 1), isEmpty);
  });

  test('a negative limit is a RangeError', () {
    expect(() => errors('{ b }', -1), throwsRangeError);
  });

  test('two operations report each on its own', () {
    expect(errors('query A { x: b } query B { y: b z: b }', 1), [
      '1:18 GQL233 The operation "B" has more than 1 aliases.',
    ]);
  });

  test('2^60 expansions saturate quickly', () {
    final fragments = [
      for (var index = 0; index < 60; index++)
        'fragment F$index on Query { ...F${index + 1} ...F${index + 1} }',
      'fragment F60 on Query { x: b }',
    ];
    final stopwatch = Stopwatch()..start();
    final result = errors('{ ...F0 } ${fragments.join(' ')}', 10);
    expect(result, [
      '1:1 GQL233 The anonymous operation has more than 10 aliases.',
    ]);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
