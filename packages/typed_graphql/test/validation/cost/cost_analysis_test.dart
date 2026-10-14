import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../schema/built.dart';

const _sliced = '''
type Query {
  users(first: Int, last: Int): [User]
    @listSize(slicingArguments: ["first", "last"], requireOneSlicingArgument: false)
}
type User { name: String friends: [User] }
''';

final class _Costs {
  const _Costs();

  OperationCost of(
    String sdl,
    String text, {
    Map<String, JsonValue> variables = const {},
    int defaultListSize = 10,
  }) {
    final schema = Built(
      sdl,
      builder: const SchemaBuilder(includesCostDirectives: true),
    ).schema;
    final document = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(Source(text)).requireDocument();
    final operation = document.definitions
        .whereType<OperationDefinition>()
        .first;
    return CostAnalysis(
      schema,
      defaultListSize: defaultListSize,
    ).costOf(document, operation, variables: variables);
  }
}

const _costs = _Costs();

void main() {
  group('the draft example', () {
    test('costs the fields and the types', () {
      // Fields: users 1 + 5 * (name 0 + friends (1 + 10 * 0)) = 6.
      // Types: Query 1 + 5 * (User 1 + name 0 + 10 * (User 1 + 0)) = 56.
      expect(
        _costs.of(_sliced, '{ users(first: 5) { name friends { name } } }'),
        const OperationCost(6, 56),
      );
    });

    test('takes the larger of two slicing arguments', () {
      // users 1 + 7 * 0 = 1; types 1 + 7 * (1 + 0) = 8.
      expect(
        _costs.of(_sliced, '{ users(first: 2, last: 7) { name } }'),
        const OperationCost(1, 8),
      );
    });
  });

  group('slicing by a variable', () {
    const text = r'query ($n: Int) { users(first: $n) { name } }';

    test('takes the given value', () {
      // Types: 1 + 3 * (1 + 0) = 4.
      expect(
        _costs.of(_sliced, text, variables: {'n': JsonNumber(3)}),
        const OperationCost(1, 4),
      );
    });

    test('takes the default of the variable without a value', () {
      // Types: 1 + 2 * (1 + 0) = 3.
      expect(
        _costs.of(
          _sliced,
          r'query ($n: Int = 2) { users(first: $n) { name } }',
        ),
        const OperationCost(1, 3),
      );
    });

    test('takes the default list size with neither', () {
      // Types: 1 + 10 * (1 + 0) = 11.
      expect(_costs.of(_sliced, text), const OperationCost(1, 11));
    });
  });

  group('list sizes', () {
    test('a slicing argument default is the size', () {
      // items 1 + 4 * 0 = 1; types 1 + 4 * (1 + 0) = 5.
      expect(
        _costs.of(
          'type Query { items(first: Int = 4): [Item] '
              '@listSize(slicingArguments: ["first"]) } type Item { id: ID }',
          '{ items { id } }',
        ),
        const OperationCost(1, 5),
      );
    });

    test('assumedSize is the size without a slicing argument', () {
      // Types: 1 + 7 * (1 + 0) = 8.
      expect(
        _costs.of(
          'type Query { items: [Item] @listSize(assumedSize: 7) } '
              'type Item { id: ID }',
          '{ items { id } }',
        ),
        const OperationCost(1, 8),
      );
    });

    test('a list without @listSize has the default list size', () {
      // Types: 1 + 3 * (1 + 0) = 4, with a default list size of 3.
      expect(
        _costs.of(
          'type Query { items: [Item] } type Item { id: ID }',
          '{ items { id } }',
          defaultListSize: 3,
        ),
        const OperationCost(1, 4),
      );
    });

    group('sizedFields', () {
      const sdl = '''
type Query {
  conn(first: Int): Conn
    @listSize(slicingArguments: ["first"], sizedFields: ["edges"], requireOneSlicingArgument: false)
}
type Conn { edges: [Edge] }
type Edge { node: Leaf }
type Leaf { id: ID }
''';

      test('the listed child has the size, the field has 1', () {
        // node 1 + 1 * 0 = 1; edges 1 + 3 * 1 = 4; conn 1 + 1 * 4 = 5.
        // Types: Query 1 + 1 * (Conn 1 + 3 * (Edge 1 + 1 * (Leaf 1))) = 8.
        expect(
          _costs.of(sdl, '{ conn(first: 3) { edges { node { id } } } }'),
          const OperationCost(5, 8),
        );
      });

      test('a fragment in the field receives the size', () {
        expect(
          _costs.of(
            sdl,
            '{ conn(first: 3) { ...F } } '
            'fragment F on Conn { edges { node { id } } }',
          ),
          const OperationCost(5, 8),
        );
      });
    });
  });

  group('weights', () {
    test('@cost on a field replaces its type weight', () {
      // Fields: 5. Types: Query 1 + 1 * (Int 0) = 1.
      expect(
        _costs.of('type Query { a: Int @cost(weight: "5") }', '{ a }'),
        const OperationCost(5, 1),
      );
    });

    test('@cost on an argument adds to the field', () {
      // Fields: a 0 + argument 3 = 3.
      expect(
        _costs.of(
          'type Query { a(x: Int @cost(weight: "3")): Int }',
          '{ a(x: 1) }',
        ),
        const OperationCost(3, 1),
      );
    });

    group('@cost on an input field', () {
      const sdl = '''
input In { v: Int @cost(weight: "2") w: Int }
type Query { a(l: [In]): Int }
''';

      test('counts each one written, inside a list', () {
        // Argument l (In, 0) + v 2 + w 0 + v 2 = 4.
        expect(
          _costs.of(sdl, '{ a(l: [{v: 1, w: 2}, {v: 3}]) }'),
          const OperationCost(4, 1),
        );
      });

      test('an unknown input field adds nothing', () {
        expect(
          _costs.of(sdl, '{ a(l: [{z: {v: 1}}]) }'),
          const OperationCost(0, 1),
        );
      });

      test('a variable adds nothing', () {
        expect(
          _costs.of(sdl, r'query ($l: [In]) { a(l: $l) }'),
          const OperationCost(0, 1),
        );
      });
    });

    test('@cost on an argument of a directive counts', () {
      expect(
        _costs.of(
          'directive @weigh(n: Int @cost(weight: "4")) on FIELD '
              'type Query { a: Int }',
          '{ a @weigh(n: 1) }',
        ),
        const OperationCost(4, 1),
      );
    });

    test('@cost on an object type is the weight of its fields', () {
      // u 7 + id 0 = 7. Types: 1 + 1 * (7 + 0) = 8.
      expect(
        _costs.of(
          'type Query { u: U } type U @cost(weight: "7") { id: ID }',
          '{ u { id } }',
        ),
        const OperationCost(7, 8),
      );
    });

    test('@cost on an enum', () {
      expect(
        _costs.of(
          'enum E @cost(weight: "4") { A } type Query { e: E }',
          '{ e }',
        ),
        const OperationCost(4, 5),
      );
    });

    test('@cost on a scalar', () {
      expect(
        _costs.of('scalar S @cost(weight: "6") type Query { s: S }', '{ s }'),
        const OperationCost(6, 7),
      );
    });

    test('a negative weight clamps the field at 0', () {
      // a max(0, -5) = 0, b 2.
      expect(
        _costs.of(
          'type Query { a: Int @cost(weight: "-5") b: Int @cost(weight: "2") }',
          '{ a b }',
        ),
        const OperationCost(2, 1),
      );
    });

    test('an interface weighs as its heaviest implementation', () {
      // n 5 + id 0 = 5. Types: 1 + 1 * (5 + 0) = 6.
      expect(
        _costs.of(
          'interface Node { id: ID } '
              'type A implements Node @cost(weight: "3") { id: ID } '
              'type B implements Node @cost(weight: "5") { id: ID } '
              'type Query { n: Node }',
          '{ n { id } }',
        ),
        const OperationCost(5, 6),
      );
    });
  });

  group('selections', () {
    test('meta-fields cost 0 and their selections are not counted', () {
      // users 1 + 1 * 0 = 1; types 1 + 1 * (1 + 0) = 2.
      expect(
        _costs.of(
          _sliced,
          '{ __typename users(first: 1) { __typename name } '
          '__schema { types { name } } }',
        ),
        const OperationCost(1, 2),
      );
    });

    test('a field the parent does not define costs 0', () {
      expect(_costs.of(_sliced, '{ nope { x } }'), const OperationCost(0, 1));
    });

    test('a fragment adds its selections', () {
      // users 1 + 2 * (friends 1 + 10 * 0) = 3. Types: 1 + 2 * (1 + 0 + 10 *
      // (1 + 0)) = 23.
      expect(
        _costs.of(
          _sliced,
          '{ users(first: 2) { ...F } } '
          'fragment F on User { name friends { name } }',
        ),
        const OperationCost(3, 23),
      );
    });

    test('an inline fragment adds its selections', () {
      expect(
        _costs.of(
          _sliced,
          '{ users(first: 2) { ... on User { name friends { name } } } }',
        ),
        const OperationCost(3, 23),
      );
    });

    test('a fragment spread twice counts twice', () {
      // users 1 + 2 * (1 + 1) = 5. Types: 1 + 2 * (1 + 10 + 10) = 43.
      expect(
        _costs.of(
          _sliced,
          '{ users(first: 2) { ...F ...F } } '
          'fragment F on User { friends { name } }',
        ),
        const OperationCost(5, 43),
      );
    });

    test('a fragment cycle counts its repeat as 0', () {
      // users 1 + 1 * (friends 1 + 10 * 0) = 2. Types: 1 + 1 * (1 + 10 *
      // (1 + 0)) = 12.
      expect(
        _costs.of(
          _sliced,
          '{ users(first: 1) { ...F } } '
          'fragment F on User { friends { ...F } }',
        ),
        const OperationCost(2, 12),
      );
    });
  });

  group('hostile documents', () {
    test('a fragment chain that expands 2^60 times is linear', () {
      final fragments = StringBuffer('fragment F0 on Query { a }');
      for (var level = 1; level <= 60; level++) {
        fragments.write(
          ' fragment F$level on Query { ...F${level - 1} ...F${level - 1} }',
        );
      }
      final cost = _costs.of(
        'type Query { a: Query }',
        '{ ...F60 } $fragments',
      );
      expect(cost.fieldCost, pow(2, 60).toDouble());
      expect(cost.typeCost, pow(2, 60).toDouble());
    });

    test('a nesting of 100000 fields does not overflow the stack', () {
      final schema = Built(
        'type Query { a: Query }',
        builder: const SchemaBuilder(includesCostDirectives: true),
      ).schema;
      var selection = Field(null, const Name('a'));
      for (var depth = 1; depth < 100000; depth++) {
        selection = Field(
          null,
          const Name('a'),
          selectionSet: SelectionSet([selection]),
        );
      }
      final operation = OperationDefinition(
        .query,
        SelectionSet([selection]),
      );
      final cost = CostAnalysis(
        schema,
      ).costOf(Document([operation]), operation);
      expect(cost, const OperationCost(100000, 100001));
    });
  });

  test('a negative default list size is a RangeError', () {
    expect(
      () => _costs.of(_sliced, '{ users { name } }', defaultListSize: -1),
      throwsRangeError,
    );
  });

  group('OperationCost', () {
    test('equal costs are equal and hash alike', () {
      expect(const OperationCost(1, 2), const OperationCost(1, 2));
      expect(
        const OperationCost(1, 2).hashCode,
        const OperationCost(1, 2).hashCode,
      );
    });

    test('different costs differ', () {
      expect(
        const OperationCost(1, 2),
        isNot(const OperationCost(1, 3)),
      );
    });

    test('prints both numbers', () {
      expect(
        const OperationCost(6, 56).toString(),
        'OperationCost(fieldCost: 6, typeCost: 56)',
      );
    });
  });
}
