import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked(
    '''
type Query {
  users(first: Int): [User] @listSize(slicingArguments: ["first"], requireOneSlicingArgument: false)
  half: Half
  a: Query
  heavy: Int @cost(weight: "50")
}
type User { name: String }
type Half { value: Int @cost(weight: "0.5") }
''',
    builder: const SchemaBuilder(includesCostDirectives: true),
  );

  List<String> errors(String text, double maxCost) =>
      checked.errors(text, [MaxCostRule(maxCost: maxCost)]);

  test('an operation at the limit is valid', () {
    expect(errors('{ users(first: 100) { name } }', 101), isEmpty);
  });

  test('an operation over by field cost only is reported', () {
    expect(errors('{ heavy }', 10), [
      '1:1 GQL238 The anonymous operation has a field cost of 50 and a type '
          'cost of 1, more than the maximum of 10.',
    ]);
  });

  test('an operation over by type cost only is reported', () {
    expect(errors('{ users(first: 100) { name } }', 100), [
      '1:1 GQL238 The anonymous operation has a field cost of 1 and a type '
          'cost of 101, more than the maximum of 100.',
    ]);
  });

  test('a negative weight lowers a cost only to zero', () {
    final onlyTypes = Checked(
      'type Query { users: [User] @listSize(assumedSize: 5) } '
      'type User { name: String @cost(weight: "-1") }',
      builder: const SchemaBuilder(includesCostDirectives: true),
    );
    expect(
      onlyTypes.errors('{ users { name } }', [const MaxCostRule(maxCost: 5)]),
      [
        '1:1 GQL238 The anonymous operation has a field cost of 1 and a type '
            'cost of 6, more than the maximum of 5.',
      ],
    );
  });

  test('a fractional cost prints with its fraction', () {
    expect(errors('{ half { value } }', 0), [
      '1:1 GQL238 The anonymous operation has a field cost of 1.5 and a type '
          'cost of 2, more than the maximum of 0.',
    ]);
  });

  test('a named operation is named in the message', () {
    expect(errors('query Q { a { a } }', 1), [
      '1:1 GQL238 The operation "Q" has a field cost of 2 and a type cost of '
          '3, more than the maximum of 1.',
    ]);
  });

  test('two operations are reported in document order', () {
    expect(errors('query A { a { a } } query B { a }', 2), [
      '1:1 GQL238 The operation "A" has a field cost of 2 and a type cost of '
          '3, more than the maximum of 2.',
    ]);
  });

  test('a fragment defined after the operation adds its cost', () {
    expect(errors('{ ...F } fragment F on Query { a { a } }', 1), [
      '1:1 GQL238 The anonymous operation has a field cost of 2 and a type '
          'cost of 3, more than the maximum of 1.',
    ]);
  });

  test('a fragment chain that expands 2^60 times reports its huge cost', () {
    final fragments = StringBuffer('fragment F0 on Query { a }');
    for (var level = 1; level <= 60; level++) {
      fragments.write(
        ' fragment F$level on Query { ...F${level - 1} ...F${level - 1} }',
      );
    }
    // 2^60 prints in exponential form, the same text on every platform.
    expect(errors('{ ...F60 } $fragments', 1000), [
      '1:1 GQL238 The anonymous operation has a field cost of '
          '1.152921504606847e+18 and a type cost of 1.152921504606847e+18, '
          'more than the maximum of 1000.',
    ]);
  });

  test('a negative or NaN maximum is an ArgumentError', () {
    expect(() => errors('{ a }', -1), throwsArgumentError);
    expect(() => errors('{ a }', double.nan), throwsArgumentError);
  });
}
