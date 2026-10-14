// Ported from graphql-js src/language/__tests__/parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../../support/dedent.dart';
import '../../support/parser_port.dart';
import '../../support/schema_nodes.dart';

void main() {
  const port = ParserPort();
  const dedent = Dedent();
  const nodes = SchemaNodes();

  group('Parser', () {
    test('creates ast from nameless query without variables', () {
      expect(
        port.parse(
          dedent('''
      query {
        node {
          id
        }
      }
    '''),
        ),
        {
          'kind': 'Document',
          'loc': nodes.loc(0, 29),
          'definitions': [
            {
              'kind': 'OperationDefinition',
              'description': null,
              'loc': nodes.loc(0, 29),
              'operation': 'query',
              'name': null,
              'variableDefinitions': null,
              'directives': null,
              'selectionSet': {
                'kind': 'SelectionSet',
                'loc': nodes.loc(6, 29),
                'selections': [
                  {
                    'kind': 'Field',
                    'loc': nodes.loc(10, 27),
                    'alias': null,
                    'name': {
                      'kind': 'Name',
                      'loc': nodes.loc(10, 14),
                      'value': 'node',
                    },
                    'arguments': null,
                    'directives': null,
                    'selectionSet': {
                      'kind': 'SelectionSet',
                      'loc': nodes.loc(15, 27),
                      'selections': [
                        {
                          'kind': 'Field',
                          'loc': nodes.loc(21, 23),
                          'alias': null,
                          'name': {
                            'kind': 'Name',
                            'loc': nodes.loc(21, 23),
                            'value': 'id',
                          },
                          'arguments': null,
                          'directives': null,
                          'selectionSet': null,
                        },
                      ],
                    },
                  },
                ],
              },
            },
          ],
        },
      );
    });

    test('creates ast from nameless query with description', () {
      expect(
        port.parse(
          dedent('''
      "Description"
      query {
        node {
          id
        }
      }
    '''),
        ),
        {
          'kind': 'Document',
          'loc': nodes.loc(0, 43),
          'definitions': [
            {
              'kind': 'OperationDefinition',
              'loc': nodes.loc(0, 43),
              'description': {
                'kind': 'StringValue',
                'loc': nodes.loc(0, 13),
                'value': 'Description',
                'block': false,
              },
              'operation': 'query',
              'name': null,
              'variableDefinitions': null,
              'directives': null,
              'selectionSet': {
                'kind': 'SelectionSet',
                'loc': nodes.loc(20, 43),
                'selections': [
                  {
                    'kind': 'Field',
                    'loc': nodes.loc(24, 41),
                    'alias': null,
                    'name': {
                      'kind': 'Name',
                      'loc': nodes.loc(24, 28),
                      'value': 'node',
                    },
                    'arguments': null,
                    'directives': null,
                    'selectionSet': {
                      'kind': 'SelectionSet',
                      'loc': nodes.loc(29, 41),
                      'selections': [
                        {
                          'kind': 'Field',
                          'loc': nodes.loc(35, 37),
                          'alias': null,
                          'name': {
                            'kind': 'Name',
                            'loc': nodes.loc(35, 37),
                            'value': 'id',
                          },
                          'arguments': null,
                          'directives': null,
                          'selectionSet': null,
                        },
                      ],
                    },
                  },
                ],
              },
            },
          ],
        },
      );
    });
  });
}
