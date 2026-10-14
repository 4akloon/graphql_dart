import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/printSchema-test.ts, the
// tests of the kinds of types and of directive definitions.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Type System Printer', () {
    test('Print Interface', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Bar',
            interfaces: [port.reference('Foo')],
            fields: [SchemaField('str', port.type('String'))],
          ),
          InterfaceType(
            'Foo',
            fields: [SchemaField('str', port.type('String'))],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Bar implements Foo {
            str: String
          }

          interface Foo {
            str: String
          }
        '''),
      );
    });

    test('Print Multiple Interface', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Bar',
            interfaces: [port.reference('Foo'), port.reference('Baz')],
            fields: [
              SchemaField('str', port.type('String')),
              SchemaField('int', port.type('Int')),
            ],
          ),
          InterfaceType(
            'Foo',
            fields: [SchemaField('str', port.type('String'))],
          ),
          InterfaceType('Baz', fields: [SchemaField('int', port.type('Int'))]),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Bar implements Foo & Baz {
            str: String
            int: Int
          }

          interface Foo {
            str: String
          }

          interface Baz {
            int: Int
          }
        '''),
      );
    });

    test('Print Hierarchical Interface', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Bar',
            interfaces: [port.reference('Foo'), port.reference('Baz')],
            fields: [
              SchemaField('str', port.type('String')),
              SchemaField('int', port.type('Int')),
            ],
          ),
          InterfaceType(
            'Foo',
            fields: [SchemaField('str', port.type('String'))],
          ),
          InterfaceType(
            'Baz',
            interfaces: [port.reference('Foo')],
            fields: [
              SchemaField('int', port.type('Int')),
              SchemaField('str', port.type('String')),
            ],
          ),
          ObjectType('Query', fields: [SchemaField('bar', port.type('Bar'))]),
        ],
        queryTypeName: 'Query',
      );
      expect(
        port.printed(schema),
        dedent('''
          type Bar implements Foo & Baz {
            str: String
            int: Int
          }

          interface Foo {
            str: String
          }

          interface Baz implements Foo {
            int: Int
            str: String
          }

          type Query {
            bar: Bar
          }
        '''),
      );
    });

    test('Print Unions', () {
      final schema = Schema(
        types: [
          UnionType('SingleUnion', memberTypes: [port.reference('Foo')]),
          ObjectType(
            'Foo',
            fields: [SchemaField('bool', port.type('Boolean'))],
          ),
          UnionType(
            'MultipleUnion',
            memberTypes: [port.reference('Foo'), port.reference('Bar')],
          ),
          ObjectType(
            'Bar',
            fields: [SchemaField('str', port.type('String'))],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          union SingleUnion = Foo

          type Foo {
            bool: Boolean
          }

          union MultipleUnion = Foo | Bar

          type Bar {
            str: String
          }
        '''),
      );
    });

    test('Print Input Type', () {
      final schema = Schema(
        types: [
          InputObjectType('InputType', fields: [port.input('int', 'Int')]),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          input InputType {
            int: Int
          }
        '''),
      );
    });

    test('Print Input Type with @oneOf directive', () {
      final schema = Schema(
        types: [
          InputObjectType(
            'InputType',
            appliedDirectives: port.applied('@oneOf'),
            fields: [port.input('int', 'Int')],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          input InputType @oneOf {
            int: Int
          }
        '''),
      );
    });

    test('Custom Scalar', () {
      final schema = Schema(types: [ScalarType('Odd')]);
      expect(port.printed(schema), 'scalar Odd');
    });

    test('Custom Scalar with specifiedByURL', () {
      final schema = Schema(
        types: [
          ScalarType(
            'Foo',
            appliedDirectives: port.applied(
              '@specifiedBy(url: "https://example.com/foo_spec")',
            ),
          ),
        ],
      );
      expect(
        port.printed(schema),
        'scalar Foo @specifiedBy(url: "https://example.com/foo_spec")',
      );
    });

    test('Enum', () {
      final schema = Schema(
        types: [
          EnumType(
            'RGB',
            values: [
              SchemaEnumValue('RED'),
              SchemaEnumValue('GREEN'),
              SchemaEnumValue('BLUE'),
            ],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          enum RGB {
            RED
            GREEN
            BLUE
          }
        '''),
      );
    });

    test('Prints empty types', () {
      final schema = Schema(
        types: [
          EnumType('SomeEnum'),
          InputObjectType('SomeInputObject'),
          InterfaceType('SomeInterface'),
          ObjectType('SomeObject'),
          UnionType('SomeUnion'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          enum SomeEnum

          input SomeInputObject

          interface SomeInterface

          type SomeObject

          union SomeUnion
        '''),
      );
    });

    test('Prints custom directives', () {
      final schema = Schema(
        directives: [
          SchemaDirective('simpleDirective', locations: [.field]),
          SchemaDirective(
            'complexDirective',
            description: 'Complex Directive',
            arguments: [
              port.input('stringArg', 'String'),
              port.input('intArg', 'Int', defaultValue: '-1'),
            ],
            isRepeatable: true,
            locations: [.field, .query],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          directive @simpleDirective on FIELD

          """Complex Directive"""
          directive @complexDirective(stringArg: String, intArg: Int = -1) repeatable on FIELD | QUERY
        '''),
      );
    });

    test('Prints deprecated directives', () {
      final schema = Schema(
        directives: [
          SchemaDirective(
            'deprecatedDirective',
            locations: [.field],
            appliedDirectives: port.applied(
              '@deprecated(reason: "Use another directive")',
            ),
          ),
        ],
      );
      expect(
        port.print(schema),
        'directive @deprecatedDirective '
        '@deprecated(reason: "Use another directive") on FIELD',
      );
    });
  });
}
