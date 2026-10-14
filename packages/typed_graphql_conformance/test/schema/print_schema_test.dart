import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/printSchema-test.ts: the
// schemas are built with the model where graphql-js uses its type
// constructors, in the order graphql-js collects the types.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Type System Printer', () {
    test('Prints String Field', () {
      final schema = port.singleField('String');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: String
          }
        '''),
      );
    });

    test('Prints [String] Field', () {
      final schema = port.singleField('[String]');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: [String]
          }
        '''),
      );
    });

    test('Prints String! Field', () {
      final schema = port.singleField('String!');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: String!
          }
        '''),
      );
    });

    test('Prints [String]! Field', () {
      final schema = port.singleField('[String]!');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: [String]!
          }
        '''),
      );
    });

    test('Prints [String!] Field', () {
      final schema = port.singleField('[String!]');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: [String!]
          }
        '''),
      );
    });

    test('Prints [String!]! Field', () {
      final schema = port.singleField('[String!]!');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: [String!]!
          }
        '''),
      );
    });

    test('Print Object Field', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Foo',
            fields: [SchemaField('str', port.type('String'))],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Foo {
            str: String
          }
        '''),
      );
    });

    test('Prints String Field With Int Arg', () {
      final schema = port.singleField(
        'String',
        arguments: [port.input('argOne', 'Int')],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int): String
          }
        '''),
      );
    });

    test('Prints String Field With Int Arg With Default', () {
      final schema = port.singleField(
        'String',
        arguments: [port.input('argOne', 'Int', defaultValue: '2')],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int = 2): String
          }
        '''),
      );
    });

    test('Prints String Field With String Arg With Default', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'String', defaultValue: r'"tes\t de\fault"'),
        ],
      );
      expect(
        port.printed(schema),
        dedent(r'''
          type Query {
            singleField(argOne: String = "tes\t de\fault"): String
          }
        '''),
      );
    });

    test('Prints String Field With Int Arg With Default Null', () {
      final schema = port.singleField(
        'String',
        arguments: [port.input('argOne', 'Int', defaultValue: 'null')],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int = null): String
          }
        '''),
      );
    });

    test('Prints String Field With Int! Arg', () {
      final schema = port.singleField(
        'String',
        arguments: [port.input('argOne', 'Int!')],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int!): String
          }
        '''),
      );
    });

    test('Prints String Field With Multiple Args', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'Int'),
          port.input('argTwo', 'String'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int, argTwo: String): String
          }
        '''),
      );
    });

    test('Prints String Field With Multiple Args, First is Default', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'Int', defaultValue: '1'),
          port.input('argTwo', 'String'),
          port.input('argThree', 'Boolean'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int = 1, argTwo: String, argThree: Boolean): String
          }
        '''),
      );
    });

    test('Prints String Field With Multiple Args, Second is Default', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'Int'),
          port.input('argTwo', 'String', defaultValue: '"foo"'),
          port.input('argThree', 'Boolean'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int, argTwo: String = "foo", argThree: Boolean): String
          }
        '''),
      );
    });

    test('Prints String Field With Multiple Args, Last is Default', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'Int'),
          port.input('argTwo', 'String'),
          port.input('argThree', 'Boolean', defaultValue: 'false'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int, argTwo: String, argThree: Boolean = false): String
          }
        '''),
      );
    });

    test('Prints schema with description', () {
      final schema = Schema(
        description: 'Schema description.',
        types: [ObjectType('Query')],
        queryTypeName: 'Query',
      );
      expect(
        port.printed(schema),
        dedent('''
          """Schema description."""
          schema {
            query: Query
          }

          type Query
        '''),
      );
    });

    test('Omits schema of common names', () {
      final schema = Schema(
        types: [
          ObjectType('Query'),
          ObjectType('Mutation'),
          ObjectType('Subscription'),
        ],
        queryTypeName: 'Query',
        mutationTypeName: 'Mutation',
        subscriptionTypeName: 'Subscription',
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query

          type Mutation

          type Subscription
        '''),
      );
    });

    test('Prints custom query root types', () {
      final schema = Schema(
        types: [ObjectType('CustomType')],
        queryTypeName: 'CustomType',
      );
      expect(
        port.printed(schema),
        dedent('''
          schema {
            query: CustomType
          }

          type CustomType
        '''),
      );
    });

    test('Prints custom mutation root types', () {
      final schema = Schema(
        types: [ObjectType('CustomType')],
        mutationTypeName: 'CustomType',
      );
      expect(
        port.printed(schema),
        dedent('''
          schema {
            mutation: CustomType
          }

          type CustomType
        '''),
      );
    });

    test('Prints custom subscription root types', () {
      final schema = Schema(
        types: [ObjectType('CustomType')],
        subscriptionTypeName: 'CustomType',
      );
      expect(
        port.printed(schema),
        dedent('''
          schema {
            subscription: CustomType
          }

          type CustomType
        '''),
      );
    });
  });
}
