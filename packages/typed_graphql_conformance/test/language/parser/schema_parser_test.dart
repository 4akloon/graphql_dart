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
    test('Simple type', () {
      final document = port.parse(
        dedent('''
      type Hello {
        world: String
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
              nodes.fieldNode(
                nodes.nameNode('world', nodes.loc(15, 20)),
                nodes.typeNode('String', nodes.loc(22, 28)),
                nodes.loc(15, 28),
              ),
            ],
            'loc': nodes.loc(0, 30),
          },
        ], nodes.loc(0, 30)),
      );
    });

    test('parses type with description string', () {
      final document = port.parse(
        dedent('''
      "Description"
      type Hello {
        world: String
      }
    '''),
      );

      expect(nodes.firstDefinition(document, 'description'), {
        'kind': 'StringValue',
        'value': 'Description',
        'block': false,
        'loc': nodes.loc(0, 13),
      });
    });

    test('parses type with description multi-line string', () {
      final document = port.parse(
        dedent('''
      """
      Description
      """
      # Even with comments between them
      type Hello {
        world: String
      }
    '''),
      );

      expect(nodes.firstDefinition(document, 'description'), {
        'kind': 'StringValue',
        'value': 'Description',
        'block': true,
        'loc': nodes.loc(0, 19),
      });
    });

    test('parses schema with description string', () {
      final document = port.parse(
        dedent('''
      "Description"
      schema {
        query: Foo
      }
    '''),
      );

      expect(nodes.firstDefinition(document, 'description'), {
        'kind': 'StringValue',
        'value': 'Description',
        'block': false,
        'loc': nodes.loc(0, 13),
      });
    });

    test('Description followed by something other than type system definition throws', () {
      expect(port.syntaxError('"Description" 1'), {
        'message': 'Syntax Error: Unexpected Int "1".',
        'locations': [
          {'line': 1, 'column': 15},
        ],
      });
    });

    test('Simple extension', () {
      final document = port.parse(
        dedent('''
      extend type Hello {
        world: String
      }
    '''),
      );

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeExtension',
            'name': nodes.nameNode('Hello', nodes.loc(12, 17)),
            'interfaces': null,
            'directives': null,
            'fields': [
              nodes.fieldNode(
                nodes.nameNode('world', nodes.loc(22, 27)),
                nodes.typeNode('String', nodes.loc(29, 35)),
                nodes.loc(22, 35),
              ),
            ],
            'loc': nodes.loc(0, 37),
          },
        ], nodes.loc(0, 37)),
      );
    });

    test('Object extension without fields', () {
      final document = port.parse('extend type Hello implements Greeting');

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeExtension',
            'name': nodes.nameNode('Hello', nodes.loc(12, 17)),
            'interfaces': [nodes.typeNode('Greeting', nodes.loc(29, 37))],
            'directives': null,
            'fields': null,
            'loc': nodes.loc(0, 37),
          },
        ], nodes.loc(0, 37)),
      );
    });

    test('Interface extension without fields', () {
      final document = port.parse('extend interface Hello implements Greeting');
      expect(
        document,
        nodes.document([
          {
            'kind': 'InterfaceTypeExtension',
            'name': nodes.nameNode('Hello', nodes.loc(17, 22)),
            'interfaces': [nodes.typeNode('Greeting', nodes.loc(34, 42))],
            'directives': null,
            'fields': null,
            'loc': nodes.loc(0, 42),
          },
        ], nodes.loc(0, 42)),
      );
    });

    test('Object extension without fields followed by extension', () {
      final document = port.parse('''

      extend type Hello implements Greeting

      extend type Hello implements SecondGreeting
    ''');

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeExtension',
            'name': nodes.nameNode('Hello', nodes.loc(19, 24)),
            'interfaces': [nodes.typeNode('Greeting', nodes.loc(36, 44))],
            'directives': null,
            'fields': null,
            'loc': nodes.loc(7, 44),
          },
          {
            'kind': 'ObjectTypeExtension',
            'name': nodes.nameNode('Hello', nodes.loc(64, 69)),
            'interfaces': [nodes.typeNode('SecondGreeting', nodes.loc(81, 95))],
            'directives': null,
            'fields': null,
            'loc': nodes.loc(52, 95),
          },
        ], nodes.loc(0, 100)),
      );
    });

    test('Extension without anything throws', () {
      expect(port.syntaxError('extend scalar Hello'), {
        'message': 'Syntax Error: Unexpected <EOF>.',
        'locations': [
          {'line': 1, 'column': 20},
        ],
      });

      expect(port.syntaxError('extend type Hello'), {
        'message': 'Syntax Error: Unexpected <EOF>.',
        'locations': [
          {'line': 1, 'column': 18},
        ],
      });

      expect(port.syntaxError('extend interface Hello'), {
        'message': 'Syntax Error: Unexpected <EOF>.',
        'locations': [
          {'line': 1, 'column': 23},
        ],
      });

      expect(port.syntaxError('extend union Hello'), {
        'message': 'Syntax Error: Unexpected <EOF>.',
        'locations': [
          {'line': 1, 'column': 19},
        ],
      });

      expect(port.syntaxError('extend enum Hello'), {
        'message': 'Syntax Error: Unexpected <EOF>.',
        'locations': [
          {'line': 1, 'column': 18},
        ],
      });

      expect(port.syntaxError('extend input Hello'), {
        'message': 'Syntax Error: Unexpected <EOF>.',
        'locations': [
          {'line': 1, 'column': 19},
        ],
      });
    });

    test('Interface extension without fields followed by extension', () {
      final document = port.parse('''

      extend interface Hello implements Greeting

      extend interface Hello implements SecondGreeting
    ''');
      expect(
        document,
        nodes.document([
          {
            'kind': 'InterfaceTypeExtension',
            'name': nodes.nameNode('Hello', nodes.loc(24, 29)),
            'interfaces': [nodes.typeNode('Greeting', nodes.loc(41, 49))],
            'directives': null,
            'fields': null,
            'loc': nodes.loc(7, 49),
          },
          {
            'kind': 'InterfaceTypeExtension',
            'name': nodes.nameNode('Hello', nodes.loc(74, 79)),
            'interfaces': [
              nodes.typeNode('SecondGreeting', nodes.loc(91, 105)),
            ],
            'directives': null,
            'fields': null,
            'loc': nodes.loc(57, 105),
          },
        ], nodes.loc(0, 110)),
      );
    });

    test('Object extension do not include descriptions', () {
      expect(
        port.syntaxError('''

      "Description"
      extend type Hello {
        world: String
      }
    '''),
        {
          'message': 'Syntax Error: Unexpected description, only GraphQL definitions support descriptions.',
          'locations': [
            {'line': 2, 'column': 7},
          ],
        },
      );

      expect(
        port.syntaxError('''

      extend "Description" type Hello {
        world: String
      }
    '''),
        {
          'message': 'Syntax Error: Unexpected String "Description".',
          'locations': [
            {'line': 2, 'column': 14},
          ],
        },
      );
    });

    test('Interface extension do not include descriptions', () {
      expect(
        port.syntaxError('''

      "Description"
      extend interface Hello {
        world: String
      }
    '''),
        {
          'message': 'Syntax Error: Unexpected description, only GraphQL definitions support descriptions.',
          'locations': [
            {'line': 2, 'column': 7},
          ],
        },
      );

      expect(
        port.syntaxError('''

      extend "Description" interface Hello {
        world: String
      }
    '''),
        {
          'message': 'Syntax Error: Unexpected String "Description".',
          'locations': [
            {'line': 2, 'column': 14},
          ],
        },
      );
    });
  });
}
