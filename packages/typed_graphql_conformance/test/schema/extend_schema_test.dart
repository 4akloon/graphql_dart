import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// the original schema, built-ins and extensions of each kind of type.
// Where graphql-js checks validateSchema, the port checks SchemaValidator.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();
  const builtIns = BuiltIns();

  group('extendSchema', () {
    test('returns the original schema when there are no type definitions', () {
      final schema = port.build('type Query');
      final result = port.extendResult(schema, '{ field }');
      // The operation is GQL100; the partial schema is the original.
      expect(port.codes(result), ['GQL100']);
      expect(result.diagnostics.single.span?.text, '{ field }');
      expect(
        result,
        isA<BuildFailure>().having(
          (failure) => failure.partial,
          'partial',
          same(schema),
        ),
      );
    });

    test('Do not modify built-in types and directives', () {
      final schema = port.build('''
        type Query {
          str: String
          int: Int
          float: Float
          id: ID
          bool: Boolean
        }
      ''');
      final extendedSchema = port.extend(
        schema,
        dedent('''
          extend type Query {
            foo: String
          }
        '''),
      );
      for (final name in ['Int', 'Float', 'String', 'Boolean', 'ID']) {
        expect(
          extendedSchema.typeNamed(name),
          same(builtIns.scalarNamed(name)),
        );
      }
      expect(extendedSchema.directives, isEmpty);
      for (final directive in builtIns.directives) {
        expect(
          extendedSchema.directiveNamed(directive.name),
          same(directive),
        );
      }
    });

    test('preserves original schema config', () {
      // The model has no `extensions` bag.
      final schema = Schema(description: 'A schema description');
      final extendedSchema = port.extend(schema, 'scalar Bar');
      expect(extendedSchema.description, 'A schema description');
    });

    test('extends objects by adding new fields', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject implements AnotherInterface & SomeInterface {
          self: SomeObject
          tree: [SomeObject]!
          """Old field description."""
          oldField: String
        }

        interface SomeInterface {
          self: SomeInterface
        }

        interface AnotherInterface {
          self: SomeObject
        }
      ''');
      final extendedSchema = port.extend(
        schema,
        dedent('''
          extend type SomeObject {
            """New field description."""
            newField(arg: Boolean): String
          }
        '''),
      );
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject implements AnotherInterface & SomeInterface {
            self: SomeObject
            tree: [SomeObject]!
            """Old field description."""
            oldField: String
            """New field description."""
            newField(arg: Boolean): String
          }
        '''),
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
    });

    test('extends objects with standard type fields', () {
      // Every schema finds every built-in scalar, whether a field uses it
      // or not.
      final schema = port.build('type Query');
      final extendedSchema = port.extend(schema, '''
        extend type Query {
          bool: Boolean
        }
      ''');
      final extendedTwiceSchema = port.extend(schema, '''
        extend type Query {
          int: Int
          float: Float
          id: ID
        }
      ''');
      expect(
        extendedSchema.typeNamed('Boolean'),
        same(builtIns.scalarNamed('Boolean')),
      );
      expect(
        port.print(extendedTwiceSchema),
        dedent('''
          type Query {
            int: Int
            float: Float
            id: ID
          }
        '''),
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
      expect(port.validationErrors(extendedTwiceSchema), isEmpty);
    });

    test('extends enums by adding new values', () {
      final schema = port.build('''
        type Query {
          someEnum(arg: SomeEnum): SomeEnum
        }

        directive @foo(arg: SomeEnum) on SCHEMA

        enum SomeEnum {
          """Old value description."""
          OLD_VALUE
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend enum SomeEnum {
          """New value description."""
          NEW_VALUE
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          enum SomeEnum {
            """Old value description."""
            OLD_VALUE
            """New value description."""
            NEW_VALUE
          }
        '''),
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
    });

    test('extends unions by adding new types', () {
      final schema = port.build('''
        type Query {
          someUnion: SomeUnion
        }

        union SomeUnion = Foo | Biz

        type Foo { foo: String }
        type Biz { biz: String }
        type Bar { bar: String }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend union SomeUnion = Bar
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        'union SomeUnion = Foo | Biz | Bar',
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
    });

    test('allows extension of union by adding itself', () {
      final schema = port.build('''
        union SomeUnion
      ''');
      final extendedSchema = port.extend(schema, '''
        extend union SomeUnion = SomeUnion
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        'union SomeUnion = SomeUnion',
      );
      expect(
        port.validate(extendedSchema),
        isA<InvalidSchema>(),
      );
    });

    test('extends inputs by adding new fields', () {
      final schema = port.build('''
        type Query {
          someInput(arg: SomeInput): String
        }

        directive @foo(arg: SomeInput) on SCHEMA

        input SomeInput {
          """Old field description."""
          oldField: String
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend input SomeInput {
          """New field description."""
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          input SomeInput {
            """Old field description."""
            oldField: String
            """New field description."""
            newField: String
          }
        '''),
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
    });

    test('extends scalars by adding new directives', () {
      // The model keeps no extension nodes; the directive is applied. The
      // spec forbids a directive that reaches itself through the types of
      // its arguments (§3.13), which graphql-js does not check: @foo takes
      // a SomeScalar, which @foo is applied to.
      final schema = port.build('''
        type Query {
          someScalar(arg: SomeScalar): SomeScalar
        }

        directive @foo(arg: SomeScalar) on SCALAR

        input FooInput {
          foo: SomeScalar
        }

        scalar SomeScalar
      ''');
      final extendedSchema = port.extend(
        schema,
        'extend scalar SomeScalar @foo',
      );
      final someScalar = port.assertType<ScalarType>(
        extendedSchema,
        'SomeScalar',
      );
      expect(
        [for (final directive in someScalar.appliedDirectives) directive.name],
        ['foo'],
      );
      expect(
        port.validationErrors(extendedSchema),
        [
          'GQL130 Directive "@foo" must not reference itself directly or indirectly.',
        ],
      );
    });

    test('extends scalars by adding specifiedBy directive', () {
      final schema = port.build('''
        type Query {
          foo: Foo
        }

        scalar Foo

        directive @foo on SCALAR
      ''');
      final extendedSchema = port.extend(
        schema,
        dedent('''
          extend scalar Foo @foo

          extend scalar Foo @specifiedBy(url: "https://example.com/foo_spec")
        '''),
      );
      final foo = port.assertType<ScalarType>(extendedSchema, 'Foo');
      expect(foo.specifiedByUrl, 'https://example.com/foo_spec');
      expect(
        port.printType(foo),
        'scalar Foo @foo @specifiedBy(url: "https://example.com/foo_spec")',
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
    });

    test('builds scalars with specifiedBy directive from extensions', () {
      final schema = Schema();
      final extendedSchema = port.extend(
        schema,
        dedent('''
          schema {
            query: Query
          }

          type Query {
            foo: Foo
          }

          scalar Foo

          extend scalar Foo @specifiedBy(url: "https://example.com/foo_spec")
        '''),
      );
      final foo = port.assertType<ScalarType>(extendedSchema, 'Foo');
      expect(foo.specifiedByUrl, 'https://example.com/foo_spec');
      expect(foo.span?.text, 'scalar Foo');
      expect(port.validationErrors(extendedSchema), isEmpty);
    });
  });
}
