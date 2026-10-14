// Ported from graphql-js src/language/__tests__/schema-parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../../support/parser_port.dart';
import '../../support/schema_nodes.dart';

void main() {
  const port = ParserPort();
  const nodes = SchemaNodes();

  group('Schema Parser', () {
    test('Schema extension', () {
      const body = '''

      extend schema {
        mutation: Mutation
      }''';
      final document = port.parse(body);
      expect(
        document,
        nodes.document([
          {
            'kind': 'SchemaExtension',
            'directives': null,
            'operationTypes': [
              {
                'kind': 'OperationTypeDefinition',
                'operation': 'mutation',
                'type': nodes.typeNode('Mutation', nodes.loc(41, 49)),
                'loc': nodes.loc(31, 49),
              },
            ],
            'loc': nodes.loc(7, 57),
          },
        ], nodes.loc(0, 57)),
      );
    });

    test('Schema extension with only directives', () {
      const body = 'extend schema @directive';
      final document = port.parse(body);
      expect(
        document,
        nodes.document([
          {
            'kind': 'SchemaExtension',
            'directives': [
              {
                'kind': 'Directive',
                'name': nodes.nameNode('directive', nodes.loc(15, 24)),
                'arguments': null,
                'loc': nodes.loc(14, 24),
              },
            ],
            'operationTypes': null,
            'loc': nodes.loc(0, 24),
          },
        ], nodes.loc(0, 24)),
      );
    });

    test('Schema extension without anything throws', () {
      expect(port.syntaxError('extend schema'), {
        'message': 'Syntax Error: Unexpected <EOF>.',
        'locations': [
          {'line': 1, 'column': 14},
        ],
      });
    });

    test('Schema extension with invalid operation type throws', () {
      expect(port.syntaxError('extend schema { unknown: SomeType }'), {
        'message': 'Syntax Error: Unexpected Name "unknown".',
        'locations': [
          {'line': 1, 'column': 17},
        ],
      });
    });
  });
}
