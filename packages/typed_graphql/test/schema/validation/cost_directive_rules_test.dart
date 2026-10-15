import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

const _builder = SchemaBuilder(includesCostDirectives: true);

final class const _Checked() {
  this;

  List<String> errors(String sdl, {bool includesCost = true}) {
    final built = Built(
      sdl,
      builder: includesCost ? _builder : const SchemaBuilder(),
    );
    final result = const SchemaValidator().validate(built.schema);
    return switch (result) {
      ValidSchema() => const [],
      InvalidSchema(:final diagnostics) => [
        for (final diagnostic in diagnostics)
          '${diagnostic.span?.location} ${diagnostic.code.id} '
              '${diagnostic.message}',
      ],
    };
  }
}

void main() {
  group('@cost weight', () {
    test('reports a weight that is not a number (GQL156)', () {
      expect(
        const _Checked().errors(
          'type Query {\n  users: Int @cost(weight: "abc")\n}',
        ),
        [
          '2:14 GQL156 The @cost weight "abc" of "Query.users" is not a '
              'number.',
        ],
      );
    });

    test('accepts integer, negative decimal and exponent weights', () {
      expect(
        const _Checked().errors('''
type Query {
  a: Int @cost(weight: "1")
  b: Int @cost(weight: "-2.5")
  c(x: Int @cost(weight: "1e3")): Int
}
'''),
        isEmpty,
      );
    });

    test('names an argument and an input field by coordinate', () {
      expect(
        const _Checked().errors('''
type Query {
  a(x: Int @cost(weight: "q")): Int
}

input In {
  f: Int @cost(weight: "z")
}
'''),
        [
          '2:12 GQL156 The @cost weight "q" of "Query.a(x:)" is not a number.',
          '6:10 GQL156 The @cost weight "z" of "In.f" is not a number.',
        ],
      );
    });

    test('names a type and an enum by their name', () {
      expect(
        const _Checked().errors('''
type Query @cost(weight: "x") {
  a: E
}

enum E @cost(weight: "y") {
  A
}
'''),
        [
          '1:12 GQL156 The @cost weight "x" of "Query" is not a number.',
          '5:8 GQL156 The @cost weight "y" of "E" is not a number.',
        ],
      );
    });
  });

  group('@cost placement', () {
    test('reports an interface field (GQL157)', () {
      expect(
        const _Checked().errors('''
type Query {
  a: Int
}

interface Node {
  id: ID @cost(weight: "1")
}
'''),
        [
          '6:10 GQL157 @cost cannot be applied to the interface field "Node.id".',
        ],
      );
    });

    test('reports an interface field argument (GQL157)', () {
      expect(
        const _Checked().errors('''
type Query {
  a: Int
}

interface Node {
  id(x: Int @cost(weight: "1")): ID
}
'''),
        [
          '6:13 GQL157 @cost cannot be applied to the interface field '
              'argument "Node.id(x:)".',
        ],
      );
    });

    test('accepts a field of an implementing object', () {
      expect(
        const _Checked().errors('''
type Query {
  a: Int
}

interface Node {
  id: ID
}

type User implements Node {
  id: ID @cost(weight: "1")
}
'''),
        isEmpty,
      );
    });
  });

  group('@listSize', () {
    test('reports a field that is not a list (GQL158)', () {
      expect(
        const _Checked().errors(
          'type Query {\n  user: Int @listSize(assumedSize: 1)\n}',
        ),
        [
          '2:13 GQL158 @listSize on "Query.user" requires a list field or '
              'sizedFields.',
        ],
      );
    });

    test('accepts a non-list with valid sizedFields', () {
      expect(
        const _Checked().errors('''
type Query {
  users: Connection @listSize(sizedFields: ["edges"])
}

type Connection {
  edges: [Int!]!
}
'''),
        isEmpty,
      );
    });

    test('reports a slicing argument that is not Int (GQL159)', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: String, last: Int): [Int] @listSize(
    slicingArguments: ["first", "missing", "last"]
  )
}
'''),
        [
          '2:42 GQL159 The slicing argument "first" of @listSize on '
              '"Query.users" is not an Int argument of the field.',
          '2:42 GQL159 The slicing argument "missing" of @listSize on '
              '"Query.users" is not an Int argument of the field.',
        ],
      );
    });

    test('accepts an Int! slicing argument', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: Int!): [Int] @listSize(slicingArguments: ["first"])
}
'''),
        isEmpty,
      );
    });

    test('reports a sized field that is not a list (GQL160)', () {
      expect(
        const _Checked().errors('''
type Query {
  users: Connection @listSize(sizedFields: ["edges", "count", "nope"])
}

type Connection {
  edges: [Int]
  count: Int
}
'''),
        [
          '2:21 GQL160 The sized field "count" of @listSize on '
              '"Query.users" is not a list field of "Connection".',
          '2:21 GQL160 The sized field "nope" of @listSize on '
              '"Query.users" is not a list field of "Connection".',
        ],
      );
    });

    test('reports assumedSize with slicing arguments (GQL161)', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: Int): [Int] @listSize(
    assumedSize: 10
    slicingArguments: ["first"]
  )
}
'''),
        [
          '2:28 GQL161 @listSize on "Query.users" gives assumedSize with '
              'slicing arguments, which needs requireOneSlicingArgument: '
              'false and slicing arguments without default values.',
        ],
      );
    });

    test('reports assumedSize when a slicing argument has a default', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: Int = 5): [Int] @listSize(
    assumedSize: 10
    slicingArguments: ["first"]
    requireOneSlicingArgument: false
  )
}
'''),
        [contains('GQL161')],
      );
    });

    test('accepts assumedSize with requireOneSlicingArgument false', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: Int): [Int] @listSize(
    assumedSize: 10
    slicingArguments: ["first"]
    requireOneSlicingArgument: false
  )
}
'''),
        isEmpty,
      );
    });
  });

  group('a bare string is a list of one', () {
    test('accepts sizedFields: "items" naming a list field', () {
      expect(
        const _Checked().errors('''
type Query { page: Page @listSize(sizedFields: "items") }
type Page { items: [Int] }
'''),
        isEmpty,
      );
    });

    test('reports a bare slicingArguments that is not an Int (GQL159)', () {
      expect(
        const _Checked().errors(
          'type Query { users(first: String): [Int] '
          '@listSize(slicingArguments: "first") }',
        ),
        [contains('GQL159 The slicing argument "first"')],
      );
    });

    test('reports a bare sizedFields that is no list field (GQL160)', () {
      expect(
        const _Checked().errors('''
type Query { page: Page @listSize(sizedFields: "count") }
type Page { count: Int }
'''),
        [contains('GQL160 The sized field "count"')],
      );
    });
  });

  test('checks the arguments of a directive definition (GQL156)', () {
    expect(
      const _Checked().errors(
        'type Query { a: Int }\n'
        'directive @tag(x: Int @cost(weight: "q")) on FIELD',
      ),
      [
        '2:23 GQL156 The @cost weight "q" of "@tag(x:)" is not a number.',
      ],
    );
  });

  test('checks nothing without the flag', () {
    expect(
      const _Checked().errors(
        'type Query {\n  a: Int @cost(weight: "abc")\n}',
        includesCost: false,
      ),
      everyElement(contains('GQL1')),
    );
    expect(
      const _Checked()
          .errors(
            'type Query {\n  a: Int @cost(weight: "abc")\n}',
            includesCost: false,
          )
          .join(),
      isNot(contains('GQL156')),
    );
  });
}
