import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  /// [sdl] built and printed by [printer].
  String reprint(String sdl, {SchemaPrinter printer = const SchemaPrinter()}) =>
      printer.print(Built(sdl).schema);

  /// The first line of each definition [printed] holds, such as
  /// `directive @include` or `scalar Int`, in order.
  /// Lines inside a block string, a description, never count.
  List<String> headsOf(String printed) {
    final head = RegExp(
      r'^(directive @\w+|schema|(scalar|type|interface|union|enum|input) \w+)',
    );
    final heads = <String>[];
    var isInBlock = false;
    for (final line in printed.split('\n')) {
      final match = isInBlock ? null : head.firstMatch(line);
      if (match != null) {
        heads.add(match[0]!);
      }
      if ('"""'.allMatches(line).length.isOdd) {
        isInBlock = !isInBlock;
      }
    }
    return heads;
  }

  test('omits a schema definition that names the default roots', () {
    const sdl = 'type Query {\n  a: Int\n}\n\ntype Mutation {\n  a: Int\n}';
    expect(reprint(sdl), sdl);
  });

  test('prints a schema definition that names other roots', () {
    const sdl = '''
schema {
  query: Root
  subscription: Events
}

type Root {
  a: Int
}

type Events {
  a: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints the schema definition when a default name is not a root', () {
    const sdl = '''
schema {
  query: Query
}

type Query {
  a: Int
}

type Mutation {
  a: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints the schema definition for a description or directives', () {
    const sdl = '''
"""The API"""
schema @key {
  query: Query
}

type Query {
  a: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints no schema definition without roots', () {
    final schema = Schema(description: 'Lost', types: [ScalarType('A')]);
    expect(const SchemaPrinter().print(schema), 'scalar A');
  });

  test('prints directive definitions before types', () {
    const sdl = '''
"""A key"""
directive @key(fields: String!, resolvable: Boolean = true) repeatable on OBJECT | INTERFACE

directive @old @deprecated on FIELD

directive @documented(
  """The reason"""
  reason: String
) on FIELD_DEFINITION

scalar Date''';
    expect(reprint(sdl), sdl);
  });

  test('prints the built-ins around the declared definitions when asked', () {
    const printer = SchemaPrinter(includesBuiltIns: true);
    final printed = reprint('''
directive @key on OBJECT
type Root { a: Int }
schema { query: Root }''', printer: printer);
    expect(headsOf(printed), [
      'schema',
      'directive @include',
      'directive @skip',
      'directive @deprecated',
      'directive @specifiedBy',
      'directive @oneOf',
      'directive @key',
      'scalar String',
      'scalar Int',
      'scalar Float',
      'scalar Boolean',
      'scalar ID',
      'type Root',
      'type __Schema',
      'type __Type',
      'enum __TypeKind',
      'type __Field',
      'type __InputValue',
      'type __EnumValue',
      'type __Directive',
      'enum __DirectiveLocation',
    ]);
  });

  test('prints @defer and @stream when the schema includes them', () {
    const printer = SchemaPrinter(includesBuiltIns: true);
    final withDefer = Schema(includesDeferAndStream: true);
    final heads = headsOf(printer.print(withDefer));
    expect(heads.sublist(5, 7), ['directive @defer', 'directive @stream']);
    expect(
      headsOf(printer.print(Schema())),
      isNot(contains('directive @defer')),
    );
  });

  test('prints a schema that builds back to the same text', () {
    const sdl = '''
"""Root"""
schema @key {
  query: Root
}

"""Marks a key"""
directive @key(fields: String = "id") repeatable on SCHEMA | OBJECT

type Root implements Node @key(fields: "id") {
  """The id"""
  id: ID!

  """Search"""
  search(
    """Text"""
    text: String = "*"
    first: Int = 10 @deprecated
  ): [Result!] @deprecated(reason: "Use find")
}

interface Node {
  id: ID!
}

union Result @key = Root

enum Color {
  RED

  """Green"""
  GREEN @deprecated
}

input Filter @oneOf {
  color: Color = RED
  list: [Int] = [1, 2]
}

scalar Url @specifiedBy(url: "https://url.spec.whatwg.org")''';
    final once = reprint(sdl);
    expect(once, sdl);
    expect(reprint(once), once);
  });

  test('prints the schema definition for a description alone', () {
    const sdl = '''
"""The API"""
schema {
  query: Query
}

type Query {
  a: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints the schema definition for directives alone', () {
    const sdl = '''
schema @key {
  query: Query
}

type Query {
  a: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints a built-in directive with its description and arguments', () {
    const printer = SchemaPrinter(includesBuiltIns: true);
    expect(
      printer.print(Schema()),
      startsWith('''
"""
Directs the executor to include this field or fragment only when the `if` argument is true.
"""
directive @include(
  """Included when true."""
  if: Boolean!
) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT'''),
    );
  });

  test('does not take a line of a description for a definition', () {
    final printed = const SchemaPrinter().print(
      Schema(types: [ScalarType('A', description: 'x\n\ntype Fake\ny')]),
    );
    expect(headsOf(printed), ['scalar A']);
  });
}
