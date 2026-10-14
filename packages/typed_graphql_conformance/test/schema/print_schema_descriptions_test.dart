import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/printSchema-test.ts, the
// tests of descriptions and of the shared viral schema.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Type System Printer', () {
    test('Prints an empty descriptions', () {
      List<InputValue> arguments() => [
        InputValue('someArg', port.type('String'), description: ''),
        InputValue('anotherArg', port.type('String'), description: ''),
      ];
      List<SchemaField> fields() => [
        SchemaField(
          'someField',
          port.type('String'),
          description: '',
          arguments: arguments(),
        ),
        SchemaField(
          'anotherField',
          port.type('String'),
          description: '',
          arguments: arguments(),
        ),
      ];
      final schema = Schema(
        description: '',
        queryTypeName: 'Query',
        types: [
          ScalarType('SomeScalar', description: ''),
          InterfaceType('SomeInterface', description: '', fields: fields()),
          UnionType(
            'SomeUnion',
            description: '',
            memberTypes: [port.reference('Query')],
          ),
          ObjectType('Query', description: '', fields: fields()),
          EnumType(
            'SomeEnum',
            description: '',
            values: [
              SchemaEnumValue('SOME_VALUE', description: ''),
              SchemaEnumValue('ANOTHER_VALUE', description: ''),
            ],
          ),
        ],
        directives: [
          SchemaDirective(
            'someDirective',
            description: '',
            arguments: arguments(),
            locations: [.query],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          """"""
          schema {
            query: Query
          }

          """"""
          directive @someDirective(
            """"""
            someArg: String

            """"""
            anotherArg: String
          ) on QUERY

          """"""
          scalar SomeScalar

          """"""
          interface SomeInterface {
            """"""
            someField(
              """"""
              someArg: String

              """"""
              anotherArg: String
            ): String

            """"""
            anotherField(
              """"""
              someArg: String

              """"""
              anotherArg: String
            ): String
          }

          """"""
          union SomeUnion = Query

          """"""
          type Query {
            """"""
            someField(
              """"""
              someArg: String

              """"""
              anotherArg: String
            ): String

            """"""
            anotherField(
              """"""
              someArg: String

              """"""
              anotherArg: String
            ): String
          }

          """"""
          enum SomeEnum {
            """"""
            SOME_VALUE

            """"""
            ANOTHER_VALUE
          }
        '''),
      );
    });

    test('Prints a description with only whitespace', () {
      final schema = port.singleField('String', description: ' ');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            " "
            singleField: String
          }
        '''),
      );
    });

    test('One-line prints a short description', () {
      final schema = port.singleField(
        'String',
        description: 'This field is awesome',
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            """This field is awesome"""
            singleField: String
          }
        '''),
      );
    });

    test('prints viral schema correctly', () {
      final schema = Schema(
        queryTypeName: 'Query',
        types: [
          ObjectType(
            'Query',
            fields: [SchemaField('viruses', port.type('[Virus!]'))],
          ),
          ObjectType(
            'Virus',
            fields: [
              SchemaField('name', port.type('String!')),
              SchemaField('knownMutations', port.type('[Mutation!]!')),
            ],
          ),
          ObjectType(
            'Mutation',
            fields: [
              SchemaField('name', port.type('String!')),
              SchemaField('geneSequence', port.type('String!')),
            ],
          ),
        ],
      );
      expect(
        port.print(schema),
        dedent('''
          schema {
            query: Query
          }

          type Query {
            viruses: [Virus!]
          }

          type Virus {
            name: String!
            knownMutations: [Mutation!]!
          }

          type Mutation {
            name: String!
            geneSequence: String!
          }
        '''),
      );
    });

    test('prints schema with description and default root operation types correctly', () {
      final schema = Schema(
        description: 'Test',
        queryTypeName: 'Query',
        types: [
          ObjectType('Query', fields: [SchemaField('a', port.type('Int'))]),
        ],
      );
      expect(
        port.print(schema),
        dedent('''
          """Test"""
          schema {
            query: Query
          }

          type Query {
            a: Int
          }
        '''),
      );
    });
  });
}
