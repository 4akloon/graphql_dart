// Ported from graphql-js src/language/__tests__/parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/ast_json.dart';
import '../../support/dedent.dart';
import '../../support/parser_port.dart';
import '../../support/schema_nodes.dart';

void main() {
  const port = ParserPort();
  const dedent = Dedent();
  const nodes = SchemaNodes();

  group('Parser', () {
    group('operation and variable definition descriptions', () {
      test('parses operation with description and variable descriptions', () {
        final document = port.document(
          dedent('''
        "Operation description"
        query myQuery(
          "Variable a description"
          \$a: Int,
          """Variable b\nmultiline description"""
          \$b: String
        ) {
          field(a: \$a, b: \$b)
        }
      '''),
        );
        final operation = document.definitions
            .whereType<OperationDefinition>()
            .first;

        expect(const AstJson().of(operation), {
          'kind': 'OperationDefinition',
          'operation': 'query',
          'description': {
            'kind': 'StringValue',
            'value': 'Operation description',
            'block': false,
            'loc': nodes.loc(0, 23),
          },
          'name': {
            'kind': 'Name',
            'value': 'myQuery',
            'loc': nodes.loc(30, 37),
          },
          'variableDefinitions': [
            {
              'kind': 'VariableDefinition',
              'description': {
                'kind': 'StringValue',
                'value': 'Variable a description',
                'block': false,
                'loc': nodes.loc(41, 65),
              },
              'variable': {
                'kind': 'Variable',
                'name': {
                  'kind': 'Name',
                  'value': 'a',
                  'loc': nodes.loc(69, 70),
                },
                'loc': nodes.loc(68, 70),
              },
              'type': {
                'kind': 'NamedType',
                'name': {
                  'kind': 'Name',
                  'value': 'Int',
                  'loc': nodes.loc(72, 75),
                },
                'loc': nodes.loc(72, 75),
              },
              'defaultValue': null,
              'directives': null,
              'loc': nodes.loc(41, 75),
            },
            {
              'kind': 'VariableDefinition',
              'description': {
                'kind': 'StringValue',
                'value': 'Variable b\nmultiline description',
                'block': true,
                'loc': nodes.loc(79, 117),
              },
              'variable': {
                'kind': 'Variable',
                'name': {
                  'kind': 'Name',
                  'value': 'b',
                  'loc': nodes.loc(121, 122),
                },
                'loc': nodes.loc(120, 122),
              },
              'type': {
                'kind': 'NamedType',
                'name': {
                  'kind': 'Name',
                  'value': 'String',
                  'loc': nodes.loc(124, 130),
                },
                'loc': nodes.loc(124, 130),
              },
              'defaultValue': null,
              'directives': null,
              'loc': nodes.loc(79, 130),
            },
          ],
          'directives': null,
          'selectionSet': {
            'kind': 'SelectionSet',
            'selections': [
              {
                'kind': 'Field',
                'alias': null,
                'name': {
                  'kind': 'Name',
                  'value': 'field',
                  'loc': nodes.loc(137, 142),
                },
                'arguments': [
                  {
                    'kind': 'Argument',
                    'name': {
                      'kind': 'Name',
                      'value': 'a',
                      'loc': nodes.loc(143, 144),
                    },
                    'value': {
                      'kind': 'Variable',
                      'name': {
                        'kind': 'Name',
                        'value': 'a',
                        'loc': nodes.loc(147, 148),
                      },
                      'loc': nodes.loc(146, 148),
                    },
                    'loc': nodes.loc(143, 148),
                  },
                  {
                    'kind': 'Argument',
                    'name': {
                      'kind': 'Name',
                      'value': 'b',
                      'loc': nodes.loc(150, 151),
                    },
                    'value': {
                      'kind': 'Variable',
                      'name': {
                        'kind': 'Name',
                        'value': 'b',
                        'loc': nodes.loc(154, 155),
                      },
                      'loc': nodes.loc(153, 155),
                    },
                    'loc': nodes.loc(150, 155),
                  },
                ],
                'directives': null,
                'selectionSet': null,
                'loc': nodes.loc(137, 156),
              },
            ],
            'loc': nodes.loc(133, 158),
          },
          'loc': nodes.loc(0, 158),
        });
      });

      test('descriptions on a short-hand query produce a sensible error', () {
        const input = '''
"""Invalid"""
        { __typename }''';

        expect(
          port.syntaxError(input)['message'],
          'Syntax Error: Unexpected description, descriptions are not supported on shorthand queries.',
        );
      });

      test(
        'parses variable definition with description, default value, and directives',
        () {
          final document = port.document(
            dedent(r'''
        query (
          "desc"
          $foo: Int = 42 @dir
        ) {
          field(foo: $foo)
        }
      '''),
          );
          final operation = document.definitions
              .whereType<OperationDefinition>()
              .first;

          expect(const AstJson().of(operation.variableDefinitions.first), {
            'kind': 'VariableDefinition',
            'defaultValue': {
              'kind': 'IntValue',
              'value': '42',
              'loc': nodes.loc(31, 33),
            },
            'directives': [
              {
                'arguments': null,
                'kind': 'Directive',
                'name': {
                  'kind': 'Name',
                  'value': 'dir',
                  'loc': nodes.loc(35, 38),
                },
                'loc': nodes.loc(34, 38),
              },
            ],
            'description': {
              'kind': 'StringValue',
              'value': 'desc',
              'block': false,
              'loc': nodes.loc(10, 16),
            },
            'variable': {
              'kind': 'Variable',
              'name': {
                'kind': 'Name',
                'value': 'foo',
                'loc': nodes.loc(20, 23),
              },
              'loc': nodes.loc(19, 23),
            },
            'type': {
              'kind': 'NamedType',
              'name': {
                'kind': 'Name',
                'value': 'Int',
                'loc': nodes.loc(25, 28),
              },
              'loc': nodes.loc(25, 28),
            },
            'loc': nodes.loc(10, 38),
          });
        },
      );
    });
  });
}
