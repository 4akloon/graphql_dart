// Ported from graphql-js src/language/__tests__/schema-parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../../support/dedent.dart';
import '../../support/parser_port.dart';
import '../../support/schema_nodes.dart';

void main() {
  const port = ParserPort();
  const dedent = Dedent();
  const nodes = SchemaNodes();

  group('Schema Parser', () {
    test('Single value enum', () {
      final document = port.parse('enum Hello { WORLD }');

      expect(
        document,
        nodes.document([
          {
            'kind': 'EnumTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
            'description': null,
            'directives': null,
            'values': [nodes.enumValueNode('WORLD', nodes.loc(13, 18))],
            'loc': nodes.loc(0, 20),
          },
        ], nodes.loc(0, 20)),
      );
    });

    test('Double value enum', () {
      final document = port.parse('enum Hello { WO, RLD }');

      expect(
        document,
        nodes.document([
          {
            'kind': 'EnumTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
            'description': null,
            'directives': null,
            'values': [
              nodes.enumValueNode('WO', nodes.loc(13, 15)),
              nodes.enumValueNode('RLD', nodes.loc(17, 20)),
            ],
            'loc': nodes.loc(0, 22),
          },
        ], nodes.loc(0, 22)),
      );
    });

    test('Simple interface', () {
      final document = port.parse(
        dedent('''
      interface Hello {
        world: String
      }
    '''),
      );

      expect(
        document,
        nodes.document([
          {
            'kind': 'InterfaceTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(10, 15)),
            'description': null,
            'interfaces': null,
            'directives': null,
            'fields': [
              nodes.fieldNode(
                nodes.nameNode('world', nodes.loc(20, 25)),
                nodes.typeNode('String', nodes.loc(27, 33)),
                nodes.loc(20, 33),
              ),
            ],
            'loc': nodes.loc(0, 35),
          },
        ], nodes.loc(0, 35)),
      );
    });

    test('Simple field with arg', () {
      final document = port.parse(
        dedent('''
      type Hello {
        world(flag: Boolean): String
      }
    '''),
      );

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
            'description': null,
            'interfaces': null,
            'directives': null,
            'fields': [
              nodes.fieldNodeWithArgs(
                nodes.nameNode('world', nodes.loc(15, 20)),
                nodes.typeNode('String', nodes.loc(37, 43)),
                [
                  nodes.inputValueNode(
                    nodes.nameNode('flag', nodes.loc(21, 25)),
                    nodes.typeNode('Boolean', nodes.loc(27, 34)),
                    null,
                    nodes.loc(21, 34),
                  ),
                ],
                nodes.loc(15, 43),
              ),
            ],
            'loc': nodes.loc(0, 45),
          },
        ], nodes.loc(0, 45)),
      );
    });

    test('Simple field with arg with default value', () {
      final document = port.parse(
        dedent('''
      type Hello {
        world(flag: Boolean = true): String
      }
    '''),
      );

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
            'description': null,
            'interfaces': null,
            'directives': null,
            'fields': [
              nodes.fieldNodeWithArgs(
                nodes.nameNode('world', nodes.loc(15, 20)),
                nodes.typeNode('String', nodes.loc(44, 50)),
                [
                  nodes.inputValueNode(
                    nodes.nameNode('flag', nodes.loc(21, 25)),
                    nodes.typeNode('Boolean', nodes.loc(27, 34)),
                    {
                      'kind': 'BooleanValue',
                      'value': true,
                      'loc': nodes.loc(37, 41),
                    },
                    nodes.loc(21, 41),
                  ),
                ],
                nodes.loc(15, 50),
              ),
            ],
            'loc': nodes.loc(0, 52),
          },
        ], nodes.loc(0, 52)),
      );
    });

    test('Simple field with list arg', () {
      final document = port.parse(
        dedent('''
      type Hello {
        world(things: [String]): String
      }
    '''),
      );

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
            'description': null,
            'interfaces': null,
            'directives': null,
            'fields': [
              nodes.fieldNodeWithArgs(
                nodes.nameNode('world', nodes.loc(15, 20)),
                nodes.typeNode('String', nodes.loc(40, 46)),
                [
                  nodes.inputValueNode(
                    nodes.nameNode('things', nodes.loc(21, 27)),
                    {
                      'kind': 'ListType',
                      'type': nodes.typeNode('String', nodes.loc(30, 36)),
                      'loc': nodes.loc(29, 37),
                    },
                    null,
                    nodes.loc(21, 37),
                  ),
                ],
                nodes.loc(15, 46),
              ),
            ],
            'loc': nodes.loc(0, 48),
          },
        ], nodes.loc(0, 48)),
      );
    });

    test('Simple field with two args', () {
      final document = port.parse(
        dedent('''
      type Hello {
        world(argOne: Boolean, argTwo: Int): String
      }
    '''),
      );

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
            'description': null,
            'interfaces': null,
            'directives': null,
            'fields': [
              nodes.fieldNodeWithArgs(
                nodes.nameNode('world', nodes.loc(15, 20)),
                nodes.typeNode('String', nodes.loc(52, 58)),
                [
                  nodes.inputValueNode(
                    nodes.nameNode('argOne', nodes.loc(21, 27)),
                    nodes.typeNode('Boolean', nodes.loc(29, 36)),
                    null,
                    nodes.loc(21, 36),
                  ),
                  nodes.inputValueNode(
                    nodes.nameNode('argTwo', nodes.loc(38, 44)),
                    nodes.typeNode('Int', nodes.loc(46, 49)),
                    null,
                    nodes.loc(38, 49),
                  ),
                ],
                nodes.loc(15, 58),
              ),
            ],
            'loc': nodes.loc(0, 60),
          },
        ], nodes.loc(0, 60)),
      );
    });

    test('Simple union', () {
      final document = port.parse('union Hello = World');

      expect(
        document,
        nodes.document([
          {
            'kind': 'UnionTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(6, 11)),
            'description': null,
            'directives': null,
            'types': [nodes.typeNode('World', nodes.loc(14, 19))],
            'loc': nodes.loc(0, 19),
          },
        ], nodes.loc(0, 19)),
      );
    });

    test('Union with two types', () {
      final document = port.parse('union Hello = Wo | Rld');

      expect(
        document,
        nodes.document([
          {
            'kind': 'UnionTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(6, 11)),
            'description': null,
            'directives': null,
            'types': [
              nodes.typeNode('Wo', nodes.loc(14, 16)),
              nodes.typeNode('Rld', nodes.loc(19, 22)),
            ],
            'loc': nodes.loc(0, 22),
          },
        ], nodes.loc(0, 22)),
      );
    });

    test('Union with two types and leading pipe', () {
      final document = port.parse('union Hello = | Wo | Rld');

      expect(
        document,
        nodes.document([
          {
            'kind': 'UnionTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(6, 11)),
            'description': null,
            'directives': null,
            'types': [
              nodes.typeNode('Wo', nodes.loc(16, 18)),
              nodes.typeNode('Rld', nodes.loc(21, 24)),
            ],
            'loc': nodes.loc(0, 24),
          },
        ], nodes.loc(0, 24)),
      );
    });

    test('Union fails with no types', () {
      expect(port.syntaxError('union Hello = |'), {
        'message': 'Syntax Error: Expected Name, found <EOF>.',
        'locations': [
          {'line': 1, 'column': 16},
        ],
      });
    });

    test('Union fails with leading double pipe', () {
      expect(port.syntaxError('union Hello = || Wo | Rld'), {
        'message': 'Syntax Error: Expected Name, found "|".',
        'locations': [
          {'line': 1, 'column': 16},
        ],
      });
    });

    test('Union fails with double pipe', () {
      expect(port.syntaxError('union Hello = Wo || Rld'), {
        'message': 'Syntax Error: Expected Name, found "|".',
        'locations': [
          {'line': 1, 'column': 19},
        ],
      });
    });

    test('Union fails with trailing pipe', () {
      expect(port.syntaxError('union Hello = | Wo | Rld |'), {
        'message': 'Syntax Error: Expected Name, found <EOF>.',
        'locations': [
          {'line': 1, 'column': 27},
        ],
      });
    });

    test('Scalar', () {
      final document = port.parse('scalar Hello');

      expect(
        document,
        nodes.document([
          {
            'kind': 'ScalarTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(7, 12)),
            'description': null,
            'directives': null,
            'loc': nodes.loc(0, 12),
          },
        ], nodes.loc(0, 12)),
      );
    });

    test('Simple input object', () {
      final document = port.parse('''

input Hello {
  world: String
}''');

      expect(
        document,
        nodes.document([
          {
            'kind': 'InputObjectTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(7, 12)),
            'description': null,
            'directives': null,
            'fields': [
              nodes.inputValueNode(
                nodes.nameNode('world', nodes.loc(17, 22)),
                nodes.typeNode('String', nodes.loc(24, 30)),
                null,
                nodes.loc(17, 30),
              ),
            ],
            'loc': nodes.loc(1, 32),
          },
        ], nodes.loc(0, 32)),
      );
    });

    test('Simple input object with args should fail', () {
      expect(
        port.syntaxError('''

      input Hello {
        world(foo: Int): String
      }
    '''),
        {
          'message': 'Syntax Error: Expected ":", found "(".',
          'locations': [
            {'line': 3, 'column': 14},
          ],
        },
      );
    });
  });
}
