import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// deprecation, new types and extensions of object types. graphql-js also
// checks validateSchema; that check returns with schema validation in M3b.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('extendSchema', () {
    test('builds types with deprecated fields/values', () {
      final extendedSchema = port.extend(Schema(), '''
        type SomeObject {
          deprecatedField: String @deprecated(reason: "not used anymore")
        }

        enum SomeEnum {
          DEPRECATED_VALUE @deprecated(reason: "do not use")
        }
      ''');
      final someType = port.assertType<ObjectType>(
        extendedSchema,
        'SomeObject',
      );
      expect(
        someType.fieldNamed('deprecatedField')?.deprecationReason,
        'not used anymore',
      );
      final someEnum = port.assertType<EnumType>(extendedSchema, 'SomeEnum');
      expect(
        someEnum.valueNamed('DEPRECATED_VALUE')?.deprecationReason,
        'do not use',
      );
    });

    test('extends objects with deprecated fields', () {
      final schema = port.build('type SomeObject');
      final extendedSchema = port.extend(schema, '''
        extend type SomeObject {
          deprecatedField: String @deprecated(reason: "not used anymore")
        }
      ''');
      final someType = port.assertType<ObjectType>(
        extendedSchema,
        'SomeObject',
      );
      expect(
        someType.fieldNamed('deprecatedField')?.deprecationReason,
        'not used anymore',
      );
    });

    test('extends enums with deprecated values', () {
      final schema = port.build('enum SomeEnum');
      final extendedSchema = port.extend(schema, '''
        extend enum SomeEnum {
          DEPRECATED_VALUE @deprecated(reason: "do not use")
        }
      ''');
      final someEnum = port.assertType<EnumType>(extendedSchema, 'SomeEnum');
      expect(
        someEnum.valueNamed('DEPRECATED_VALUE')?.deprecationReason,
        'do not use',
      );
    });

    test('adds new unused types', () {
      final schema = port.build('''
        type Query {
          dummy: String
        }
      ''');
      final extensionSdl = dedent('''
        type DummyUnionMember {
          someField: String
        }

        enum UnusedEnum {
          SOME_VALUE
        }

        input UnusedInput {
          someField: String
        }

        interface UnusedInterface {
          someField: String
        }

        type UnusedObject {
          someField: String
        }

        union UnusedUnion = DummyUnionMember
      ''');
      final extendedSchema = port.extend(schema, extensionSdl);
      expect(port.schemaChanges(schema, extendedSchema), extensionSdl);
    });

    test('extends objects by adding new fields with arguments', () {
      final schema = port.build('''
        type SomeObject

        type Query {
          someObject: SomeObject
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        input NewInputObj {
          field1: Int
          field2: [Float]
          field3: String!
        }

        extend type SomeObject {
          newField(arg1: String, arg2: NewInputObj!): String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject {
            newField(arg1: String, arg2: NewInputObj!): String
          }

          input NewInputObj {
            field1: Int
            field2: [Float]
            field3: String!
          }
        '''),
      );
    });

    test('extends objects by adding new fields with existing types', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject
        enum SomeEnum { VALUE }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend type SomeObject {
          newField(arg1: SomeEnum!): SomeEnum
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject {
            newField(arg1: SomeEnum!): SomeEnum
          }
        '''),
      );
    });

    test('extends objects by adding implemented interfaces', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject {
          foo: String
        }

        interface SomeInterface {
          foo: String
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend type SomeObject implements SomeInterface
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject implements SomeInterface {
            foo: String
          }
        '''),
      );
    });

    test('extends objects by including new types', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject {
          oldField: String
        }
      ''');
      final newTypesSdl = dedent('''
        enum NewEnum {
          VALUE
        }

        interface NewInterface {
          baz: String
        }

        type NewObject implements NewInterface {
          baz: String
        }

        scalar NewScalar

        union NewUnion = NewObject
      ''');
      final extendedSchema = port.extend(schema, '''
$newTypesSdl
        extend type SomeObject {
          newObject: NewObject
          newInterface: NewInterface
          newUnion: NewUnion
          newScalar: NewScalar
          newEnum: NewEnum
          newTree: [SomeObject]!
        }
      ''');
      final changes = dedent('''
        type SomeObject {
          oldField: String
          newObject: NewObject
          newInterface: NewInterface
          newUnion: NewUnion
          newScalar: NewScalar
          newEnum: NewEnum
          newTree: [SomeObject]!
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        '$changes\n\n$newTypesSdl',
      );
    });

    test('extends objects by adding implemented new interfaces', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject implements OldInterface {
          oldField: String
        }

        interface OldInterface {
          oldField: String
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend type SomeObject implements NewInterface {
          newField: String
        }

        interface NewInterface {
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject implements OldInterface & NewInterface {
            oldField: String
            newField: String
          }

          interface NewInterface {
            newField: String
          }
        '''),
      );
    });
  });
}
