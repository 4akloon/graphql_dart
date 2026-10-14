import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  /// [sdl] built and printed.
  String reprint(String sdl) => const SchemaPrinter().print(Built(sdl).schema);

  test('prints every kind of type, in declaration order', () {
    const sdl = '''
scalar Date

type Query implements Node & Entity {
  id: ID!
  tags: [String!]!
}

interface Node implements Entity {
  id: ID!
}

union Result = Query | Node

enum Color {
  RED
  GREEN
}

input Filter {
  color: Color = RED
  limit: Int = 10
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints a type without members without braces', () {
    const sdl =
        'type Empty\n\ninterface Nothing\n\nunion None\n\nenum E\n\n'
        'input In';
    expect(reprint(sdl), sdl);
  });

  test('prints arguments on one line without descriptions', () {
    const sdl = '''
type Query {
  hero(episode: Episode = JEDI, first: Int! = 3, filter: In = { a: [1, 2] }): String
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints arguments on their own lines when one has a description', () {
    const sdl = '''
type Query {
  hero(
    """Which one"""
    episode: Episode
    first: Int
  ): String
}''';
    expect(reprint(sdl), sdl);
  });

  test('puts a blank line before a described member that is not first', () {
    const sdl = '''
"""A type"""
type Query {
  """First"""
  a: Int

  """Second"""
  b(
    """Argument"""
    x: Int

    """Other"""
    y: Int
  ): Int
  c: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints a description that cannot be a block string as quoted', () {
    final schema = Schema(
      types: [ScalarType('A', description: 'Ends with a break\n')],
    );
    expect(
      const SchemaPrinter().print(schema),
      '"Ends with a break\\n"\n'
      'scalar A',
    );
  });

  test('prints a multi-line description as a block, indented', () {
    const sdl = '''
type Query {
  """
  Line one

  Line three
  """
  a: Int
}''';
    expect(reprint(sdl), sdl.replaceFirst('one\n\n', 'one\n  \n'));
  });

  test('prints applied directives as written', () {
    const sdl = '''
scalar Date @specifiedBy(url: "https://example.com") @key

type Query @key(fields: "id") {
  a(x: Int @deprecated): Int @deprecated(reason: "No longer supported")
}

union U @key = Query

enum E @key {
  A @deprecated
}

input In @oneOf {
  a: Int @deprecated(reason: "Use b")
}''';
    expect(reprint(sdl), sdl);
  });
}
