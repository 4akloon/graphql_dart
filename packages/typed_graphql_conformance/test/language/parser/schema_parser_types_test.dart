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
    test('Simple non-null type', () {
      final document = port.parse(
        dedent('''
      type Hello {
        world: String!
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
                {
                  'kind': 'NonNullType',
                  'type': nodes.typeNode('String', nodes.loc(22, 28)),
                  'loc': nodes.loc(22, 29),
                },
                nodes.loc(15, 29),
              ),
            ],
            'loc': nodes.loc(0, 31),
          },
        ], nodes.loc(0, 31)),
      );
    });

    test('Simple interface inheriting interface', () {
      final document = port.parse(
        'interface Hello implements World { field: String }',
      );
      expect(
        document,
        nodes.document([
          {
            'kind': 'InterfaceTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(10, 15)),
            'description': null,
            'interfaces': [nodes.typeNode('World', nodes.loc(27, 32))],
            'directives': null,
            'fields': [
              nodes.fieldNode(
                nodes.nameNode('field', nodes.loc(35, 40)),
                nodes.typeNode('String', nodes.loc(42, 48)),
                nodes.loc(35, 48),
              ),
            ],
            'loc': nodes.loc(0, 50),
          },
        ], nodes.loc(0, 50)),
      );
    });

    test('Simple type inheriting interface', () {
      final document = port.parse(
        'type Hello implements World { field: String }',
      );

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
            'description': null,
            'interfaces': [nodes.typeNode('World', nodes.loc(22, 27))],
            'directives': null,
            'fields': [
              nodes.fieldNode(
                nodes.nameNode('field', nodes.loc(30, 35)),
                nodes.typeNode('String', nodes.loc(37, 43)),
                nodes.loc(30, 43),
              ),
            ],
            'loc': nodes.loc(0, 45),
          },
        ], nodes.loc(0, 45)),
      );
    });

    test('Simple type inheriting multiple interfaces', () {
      final document = port.parse(
        'type Hello implements Wo & rld { field: String }',
      );

      expect(
        document,
        nodes.document([
          {
            'kind': 'ObjectTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
            'description': null,
            'interfaces': [
              nodes.typeNode('Wo', nodes.loc(22, 24)),
              nodes.typeNode('rld', nodes.loc(27, 30)),
            ],
            'directives': null,
            'fields': [
              nodes.fieldNode(
                nodes.nameNode('field', nodes.loc(33, 38)),
                nodes.typeNode('String', nodes.loc(40, 46)),
                nodes.loc(33, 46),
              ),
            ],
            'loc': nodes.loc(0, 48),
          },
        ], nodes.loc(0, 48)),
      );
    });

    test('Simple interface inheriting multiple interfaces', () {
      final document = port.parse(
        'interface Hello implements Wo & rld { field: String }',
      );
      expect(
        document,
        nodes.document([
          {
            'kind': 'InterfaceTypeDefinition',
            'name': nodes.nameNode('Hello', nodes.loc(10, 15)),
            'description': null,
            'interfaces': [
              nodes.typeNode('Wo', nodes.loc(27, 29)),
              nodes.typeNode('rld', nodes.loc(32, 35)),
            ],
            'directives': null,
            'fields': [
              nodes.fieldNode(
                nodes.nameNode('field', nodes.loc(38, 43)),
                nodes.typeNode('String', nodes.loc(45, 51)),
                nodes.loc(38, 51),
              ),
            ],
            'loc': nodes.loc(0, 53),
          },
        ], nodes.loc(0, 53)),
      );
    });

    test(
      'Simple type inheriting multiple interfaces with leading ampersand',
      () {
        final document = port.parse(
          'type Hello implements & Wo & rld { field: String }',
        );

        expect(
          document,
          nodes.document([
            {
              'kind': 'ObjectTypeDefinition',
              'name': nodes.nameNode('Hello', nodes.loc(5, 10)),
              'description': null,
              'interfaces': [
                nodes.typeNode('Wo', nodes.loc(24, 26)),
                nodes.typeNode('rld', nodes.loc(29, 32)),
              ],
              'directives': null,
              'fields': [
                nodes.fieldNode(
                  nodes.nameNode('field', nodes.loc(35, 40)),
                  nodes.typeNode('String', nodes.loc(42, 48)),
                  nodes.loc(35, 48),
                ),
              ],
              'loc': nodes.loc(0, 50),
            },
          ], nodes.loc(0, 50)),
        );
      },
    );

    test(
      'Simple interface inheriting multiple interfaces with leading ampersand',
      () {
        final document = port.parse(
          'interface Hello implements & Wo & rld { field: String }',
        );
        expect(
          document,
          nodes.document([
            {
              'kind': 'InterfaceTypeDefinition',
              'name': nodes.nameNode('Hello', nodes.loc(10, 15)),
              'description': null,
              'interfaces': [
                nodes.typeNode('Wo', nodes.loc(29, 31)),
                nodes.typeNode('rld', nodes.loc(34, 37)),
              ],
              'directives': null,
              'fields': [
                nodes.fieldNode(
                  nodes.nameNode('field', nodes.loc(40, 45)),
                  nodes.typeNode('String', nodes.loc(47, 53)),
                  nodes.loc(40, 53),
                ),
              ],
              'loc': nodes.loc(0, 55),
            },
          ], nodes.loc(0, 55)),
        );
      },
    );
  });
}
