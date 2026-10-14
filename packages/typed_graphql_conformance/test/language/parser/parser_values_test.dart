// Ported from graphql-js src/language/__tests__/parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../../support/parser_port.dart';
import '../../support/schema_nodes.dart';

void main() {
  const port = ParserPort();
  const nodes = SchemaNodes();

  group('Parser', () {
    group('parseValue', () {
      test('parses null value', () {
        expect(port.parseValue('null'), {
          'kind': 'NullValue',
          'loc': nodes.loc(0, 4),
        });
      });

      test('parses list values', () {
        expect(port.parseValue('[123 "abc"]'), {
          'kind': 'ListValue',
          'loc': nodes.loc(0, 11),
          'values': [
            {
              'kind': 'IntValue',
              'loc': nodes.loc(1, 4),
              'value': '123',
            },
            {
              'kind': 'StringValue',
              'loc': nodes.loc(5, 10),
              'value': 'abc',
              'block': false,
            },
          ],
        });
      });

      test('parses block strings', () {
        expect(port.parseValue('["""long""" "short"]'), {
          'kind': 'ListValue',
          'loc': nodes.loc(0, 20),
          'values': [
            {
              'kind': 'StringValue',
              'loc': nodes.loc(1, 11),
              'value': 'long',
              'block': true,
            },
            {
              'kind': 'StringValue',
              'loc': nodes.loc(12, 19),
              'value': 'short',
              'block': false,
            },
          ],
        });
      });

      test('allows variables', () {
        expect(port.parseValue(r'{ field: $var }'), {
          'kind': 'ObjectValue',
          'loc': nodes.loc(0, 15),
          'fields': [
            {
              'kind': 'ObjectField',
              'loc': nodes.loc(2, 13),
              'name': {
                'kind': 'Name',
                'loc': nodes.loc(2, 7),
                'value': 'field',
              },
              'value': {
                'kind': 'Variable',
                'loc': nodes.loc(9, 13),
                'name': {
                  'kind': 'Name',
                  'loc': nodes.loc(10, 13),
                  'value': 'var',
                },
              },
            },
          ],
        });
      });

      test('correct message for incomplete variable', () {
        expect(port.valueSyntaxError(r'$'), {
          'message': 'Syntax Error: Expected Name, found <EOF>.',
          'locations': [
            {'line': 1, 'column': 2},
          ],
        });
      });

      test('correct message for unexpected token', () {
        expect(port.valueSyntaxError(':'), {
          'message': 'Syntax Error: Unexpected ":".',
          'locations': [
            {'line': 1, 'column': 1},
          ],
        });
      });
    });

    group('parseConstValue', () {
      test('parses values', () {
        expect(port.parseConstValue('[123 "abc"]'), {
          'kind': 'ListValue',
          'loc': nodes.loc(0, 11),
          'values': [
            {
              'kind': 'IntValue',
              'loc': nodes.loc(1, 4),
              'value': '123',
            },
            {
              'kind': 'StringValue',
              'loc': nodes.loc(5, 10),
              'value': 'abc',
              'block': false,
            },
          ],
        });
      });

      test('does not allow variables', () {
        expect(port.constValueSyntaxError(r'{ field: $var }'), {
          'message':
              r'Syntax Error: Unexpected variable "$var" in constant value.',
          'locations': [
            {'line': 1, 'column': 10},
          ],
        });
      });

      test('correct message for unexpected token', () {
        expect(port.constValueSyntaxError(r'$'), {
          'message': r'Syntax Error: Unexpected "$".',
          'locations': [
            {'line': 1, 'column': 1},
          ],
        });
      });
    });

    group('parseType', () {
      test('parses well known types', () {
        expect(port.parseType('String'), {
          'kind': 'NamedType',
          'loc': nodes.loc(0, 6),
          'name': {
            'kind': 'Name',
            'loc': nodes.loc(0, 6),
            'value': 'String',
          },
        });
      });

      test('parses custom types', () {
        expect(port.parseType('MyType'), {
          'kind': 'NamedType',
          'loc': nodes.loc(0, 6),
          'name': {
            'kind': 'Name',
            'loc': nodes.loc(0, 6),
            'value': 'MyType',
          },
        });
      });

      test('parses list types', () {
        expect(port.parseType('[MyType]'), {
          'kind': 'ListType',
          'loc': nodes.loc(0, 8),
          'type': {
            'kind': 'NamedType',
            'loc': nodes.loc(1, 7),
            'name': {
              'kind': 'Name',
              'loc': nodes.loc(1, 7),
              'value': 'MyType',
            },
          },
        });
      });

      test('parses non-null types', () {
        expect(port.parseType('MyType!'), {
          'kind': 'NonNullType',
          'loc': nodes.loc(0, 7),
          'type': {
            'kind': 'NamedType',
            'loc': nodes.loc(0, 6),
            'name': {
              'kind': 'Name',
              'loc': nodes.loc(0, 6),
              'value': 'MyType',
            },
          },
        });
      });

      test('parses nested types', () {
        expect(port.parseType('[MyType!]'), {
          'kind': 'ListType',
          'loc': nodes.loc(0, 9),
          'type': {
            'kind': 'NonNullType',
            'loc': nodes.loc(1, 8),
            'type': {
              'kind': 'NamedType',
              'loc': nodes.loc(1, 7),
              'name': {
                'kind': 'Name',
                'loc': nodes.loc(1, 7),
                'value': 'MyType',
              },
            },
          },
        });
      });
    });
  });
}
