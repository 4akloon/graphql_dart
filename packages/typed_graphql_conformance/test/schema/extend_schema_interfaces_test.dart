import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// repeated extensions, interfaces, root types and directives. Where
// graphql-js checks validateSchema, the port checks SchemaValidator.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('extendSchema', () {
    test('extends different types multiple times', () {
      final schema = port.build('''
        type Query {
          someScalar: SomeScalar
          someObject(someInput: SomeInput): SomeObject
          someInterface: SomeInterface
          someEnum: SomeEnum
          someUnion: SomeUnion
        }

        scalar SomeScalar

        type SomeObject implements SomeInterface {
          oldField: String
        }

        interface SomeInterface {
          oldField: String
        }

        enum SomeEnum {
          OLD_VALUE
        }

        union SomeUnion = SomeObject

        input SomeInput {
          oldField: String
        }
      ''');
      final newTypesSdl = dedent('''
        scalar NewScalar

        scalar AnotherNewScalar

        type NewObject {
          foo: String
        }

        type AnotherNewObject {
          foo: String
        }

        interface NewInterface {
          newField: String
        }

        interface AnotherNewInterface {
          anotherNewField: String
        }
      ''');
      final schemaWithNewTypes = port.extend(schema, newTypesSdl);
      expect(port.schemaChanges(schema, schemaWithNewTypes), newTypesSdl);

      final extendedSchema = port.extend(schemaWithNewTypes, '''
        extend scalar SomeScalar @specifiedBy(url: "http://example.com/foo_spec")

        extend type SomeObject implements NewInterface {
          newField: String
        }

        extend type SomeObject implements AnotherNewInterface {
          anotherNewField: String
        }

        extend enum SomeEnum {
          NEW_VALUE
        }

        extend enum SomeEnum {
          ANOTHER_NEW_VALUE
        }

        extend union SomeUnion = NewObject

        extend union SomeUnion = AnotherNewObject

        extend input SomeInput {
          newField: String
        }

        extend input SomeInput {
          anotherNewField: String
        }
      ''');
      final changes = dedent('''
        scalar SomeScalar @specifiedBy(url: "http://example.com/foo_spec")

        type SomeObject implements SomeInterface & NewInterface & AnotherNewInterface {
          oldField: String
          newField: String
          anotherNewField: String
        }

        enum SomeEnum {
          OLD_VALUE
          NEW_VALUE
          ANOTHER_NEW_VALUE
        }

        union SomeUnion = SomeObject | NewObject | AnotherNewObject

        input SomeInput {
          oldField: String
          newField: String
          anotherNewField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        '$changes\n\n$newTypesSdl',
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
    });

    test('extends interfaces by adding new fields', () {
      final schema = port.build('''
        interface SomeInterface {
          oldField: String
        }

        interface AnotherInterface implements SomeInterface {
          oldField: String
        }

        type SomeObject implements SomeInterface & AnotherInterface {
          oldField: String
        }

        type Query {
          someInterface: SomeInterface
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend interface SomeInterface {
          newField: String
        }

        extend interface AnotherInterface {
          newField: String
        }

        extend type SomeObject {
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          interface SomeInterface {
            oldField: String
            newField: String
          }

          interface AnotherInterface implements SomeInterface {
            oldField: String
            newField: String
          }

          type SomeObject implements SomeInterface & AnotherInterface {
            oldField: String
            newField: String
          }
        '''),
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
    });

    test('extends interfaces by adding new implemented interfaces', () {
      final schema = port.build('''
        interface SomeInterface {
          oldField: String
        }

        interface AnotherInterface implements SomeInterface {
          oldField: String
        }

        type SomeObject implements SomeInterface & AnotherInterface {
          oldField: String
        }

        type Query {
          someInterface: SomeInterface
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        interface NewInterface {
          newField: String
        }

        extend interface AnotherInterface implements NewInterface {
          newField: String
        }

        extend type SomeObject implements NewInterface {
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          interface AnotherInterface implements SomeInterface & NewInterface {
            oldField: String
            newField: String
          }

          type SomeObject implements SomeInterface & AnotherInterface & NewInterface {
            oldField: String
            newField: String
          }

          interface NewInterface {
            newField: String
          }
        '''),
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
    });

    test('allows extension of interface with missing Object fields', () {
      final schema = port.build('''
        type Query {
          someInterface: SomeInterface
        }

        type SomeObject implements SomeInterface {
          oldField: SomeInterface
        }

        interface SomeInterface {
          oldField: SomeInterface
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend interface SomeInterface {
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          interface SomeInterface {
            oldField: SomeInterface
            newField: String
          }
        '''),
      );
      expect(
        port.validate(extendedSchema),
        isA<InvalidSchema>(),
      );
    });

    test('extends interfaces multiple times', () {
      final schema = port.build('''
        type Query {
          someInterface: SomeInterface
        }

        interface SomeInterface {
          some: SomeInterface
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend interface SomeInterface {
          newFieldA: Int
        }

        extend interface SomeInterface {
          newFieldB(test: Boolean): String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          interface SomeInterface {
            some: SomeInterface
            newFieldA: Int
            newFieldB(test: Boolean): String
          }
        '''),
      );
      expect(port.validationErrors(extendedSchema), isEmpty);
    });

    test('may extend mutations and subscriptions', () {
      final mutationSchema = port.build('''
        type Query {
          queryField: String
        }

        type Mutation {
          mutationField: String
        }

        type Subscription {
          subscriptionField: String
        }
      ''');
      final originalPrint = port.print(mutationSchema);
      final extendedSchema = port.extend(mutationSchema, '''
        extend type Query {
          newQueryField: Int
        }

        extend type Mutation {
          newMutationField: Int
        }

        extend type Subscription {
          newSubscriptionField: Int
        }
      ''');
      expect(extendedSchema, isNot(same(mutationSchema)));
      expect(port.print(mutationSchema), originalPrint);
      expect(
        port.print(extendedSchema),
        dedent('''
          type Query {
            queryField: String
            newQueryField: Int
          }

          type Mutation {
            mutationField: String
            newMutationField: Int
          }

          type Subscription {
            subscriptionField: String
            newSubscriptionField: Int
          }
        '''),
      );
    });

    test('may extend directives with new directive', () {
      final schema = port.build('''
        type Query {
          foo: String
        }
      ''');
      final extensionSdl = dedent('''
        """New directive."""
        directive @new(enable: Boolean!, tag: String) repeatable on QUERY | FIELD
      ''');
      final extendedSchema = port.extend(schema, extensionSdl);
      expect(port.schemaChanges(schema, extendedSchema), extensionSdl);
      expect(port.validationErrors(extendedSchema), isEmpty);
    });
  });
}
