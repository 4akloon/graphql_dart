import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: root types,
// fields and arguments. Locations are compared as graphql-js reports them;
// mapping/schema.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Type System: A Schema must have Object root types', () {
    test('accepts a Schema whose query type is an object type', () {
      final schema = port.build('''
      type Query {
        test: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
      final schemaWithDef = port.build('''
      schema {
        query: QueryRoot
      }

      type QueryRoot {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), isEmpty);
    });

    test(
      'accepts a Schema whose query and mutation types are object types',
      () {
        final schema = port.build('''
      type Query {
        test: String
      }

      type Mutation {
        test: String
      }
    ''');
        expect(port.errors(schema), isEmpty);
        final schemaWithDef = port.build('''
      schema {
        query: QueryRoot
        mutation: MutationRoot
      }

      type QueryRoot {
        test: String
      }

      type MutationRoot {
        test: String
      }
    ''');
        expect(port.errors(schemaWithDef), isEmpty);
      },
    );

    test(
      'accepts a Schema whose query and subscription types are object types',
      () {
        final schema = port.build('''
      type Query {
        test: String
      }

      type Subscription {
        test: String
      }
    ''');
        expect(port.errors(schema), isEmpty);
        final schemaWithDef = port.build('''
      schema {
        query: QueryRoot
        subscription: SubscriptionRoot
      }

      type QueryRoot {
        test: String
      }

      type SubscriptionRoot {
        test: String
      }
    ''');
        expect(port.errors(schemaWithDef), isEmpty);
      },
    );

    test('rejects a Schema without a query type', () {
      final schema = port.build('''
      type Mutation {
        test: String
      }
    ''');
      expect(port.errors(schema), [
        'Query root type must be provided.',
      ]);
      final schemaWithDef = port.build('''
      schema {
        mutation: MutationRoot
      }

      type MutationRoot {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), [
        'Query root type must be provided. @ 2:7',
      ]);
    });

    test('rejects a Schema whose query root type is not an Object type', () {
      final schema = port.build('''
      input Query {
        test: String
      }
    ''');
      expect(port.errors(schema), [
        'Query root type must be Object type, it cannot be Query. @ 2:7',
      ]);
      final schemaWithDef = port.build('''
      schema {
        query: SomeInputObject
      }

      input SomeInputObject {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), [
        'Query root type must be Object type, it cannot be '
            'SomeInputObject. @ 3:16',
      ]);
    });

    test('rejects a Schema whose mutation type is an input type', () {
      final schema = port.build('''
      type Query {
        field: String
      }

      input Mutation {
        test: String
      }
    ''');
      expect(port.errors(schema), [
        'Mutation root type must be Object type if provided, it cannot '
            'be Mutation. @ 6:7',
      ]);
      final schemaWithDef = port.build('''
      schema {
        query: Query
        mutation: SomeInputObject
      }

      type Query {
        field: String
      }

      input SomeInputObject {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), [
        'Mutation root type must be Object type if provided, it cannot '
            'be SomeInputObject. @ 4:19',
      ]);
    });

    test('rejects a Schema whose subscription type is an input type', () {
      final schema = port.build('''
      type Query {
        field: String
      }

      input Subscription {
        test: String
      }
    ''');
      expect(port.errors(schema), [
        'Subscription root type must be Object type if provided, it '
            'cannot be Subscription. @ 6:7',
      ]);
      final schemaWithDef = port.build('''
      schema {
        query: Query
        subscription: SomeInputObject
      }

      type Query {
        field: String
      }

      input SomeInputObject {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), [
        'Subscription root type must be Object type if provided, it '
            'cannot be SomeInputObject. @ 4:23',
      ]);
    });

    test('rejects a Schema extended with invalid root types', () {
      var schema = port.build('''
      input SomeInputObject {
        test: String
      }

      scalar SomeScalar

      enum SomeEnum {
        ENUM_VALUE
      }
    ''');
      schema = port.extend(schema, '''
        extend schema {
          query: SomeInputObject
        }
      ''');
      schema = port.extend(schema, '''
        extend schema {
          mutation: SomeScalar
        }
      ''');
      schema = port.extend(schema, '''
        extend schema {
          subscription: SomeEnum
        }
      ''');
      expect(port.errors(schema), [
        'Query root type must be Object type, it cannot be '
            'SomeInputObject. @ 3:18',
        'Mutation root type must be Object type if provided, it cannot '
            'be SomeScalar. @ 3:21',
        'Subscription root type must be Object type if provided, it '
            'cannot be SomeEnum. @ 3:25',
      ]);
    });

    test('rejects a Schema whose directives have empty locations', () {
      final schema = Schema(
        types: port.someTypes,
        directives: [SchemaDirective('BadDirective')],
        queryTypeName: 'SomeObject',
      );
      expect(port.errors(schema), [
        'Directive @BadDirective must include 1 or more locations.',
      ]);
    });
  });

  group('Type System: Root types must all be different if provided', () {
    test('accepts a Schema with different root types', () {
      final schema = port.build('''
      type SomeObject1 {
        field: String
      }

      type SomeObject2 {
        field: String
      }

      type SomeObject3 {
        field: String
      }

      schema {
        query: SomeObject1
        mutation: SomeObject2
        subscription: SomeObject3
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test(
      'rejects a Schema where the same type is used for multiple root types',
      () {
        final schema = port.build('''
      type SomeObject {
        field: String
      }

      type UniqueObject {
        field: String
      }

      schema {
        query: SomeObject
        mutation: UniqueObject
        subscription: SomeObject
      }
    ''');
        expect(port.errors(schema), [
          'All root types must be different, "SomeObject" type is used as '
              'query and subscription root types. @ 11:16 13:23',
        ]);
      },
    );

    test('rejects a Schema where the same type is used for all root types', () {
      final schema = port.build('''
      type SomeObject {
        field: String
      }

      schema {
        query: SomeObject
        mutation: SomeObject
        subscription: SomeObject
      }
    ''');
      expect(port.errors(schema), [
        'All root types must be different, "SomeObject" type is used as '
            'query, mutation, and subscription root types. @ 7:16 8:19 9:23',
      ]);
    });
  });

  group('Type System: Objects must have fields', () {
    test('accepts an Object type with fields object', () {
      final schema = port.build('''
      type Query {
        field: SomeObject
      }

      type SomeObject {
        field: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Object type with missing fields', () {
      final schema = port.build('''
      type Query {
        test: IncompleteObject
      }

      type IncompleteObject
    ''');
      expect(port.errors(schema), [
        'Type IncompleteObject must define one or more fields. @ 6:7',
      ]);
      final manualSchema = port.withFieldType(ObjectType('IncompleteObject'));
      expect(port.errors(manualSchema), [
        'Type IncompleteObject must define one or more fields.',
      ]);
    });

    test('rejects an Object type with incorrectly named fields', () {
      final schema = port.withFieldType(
        ObjectType(
          'SomeObject',
          fields: [SchemaField('__badName', schemas.type('String'))],
        ),
      );
      expect(port.errors(schema), [
        'Name "__badName" must not begin with "__", which is '
            'reserved by GraphQL introspection.',
      ]);
    });
  });

  group('Type System: Fields args must be properly named', () {
    test('accepts field args with valid names', () {
      final schema = port.withFieldType(
        ObjectType(
          'SomeObject',
          fields: [
            SchemaField(
              'goodField',
              schemas.type('String'),
              arguments: [schemas.input('goodArg', 'String')],
            ),
          ],
        ),
      );
      expect(port.errors(schema), isEmpty);
    });

    test('rejects field arg with invalid names', () {
      final schema = port.withFieldType(
        ObjectType(
          'SomeObject',
          fields: [
            SchemaField(
              'badField',
              schemas.type('String'),
              arguments: [schemas.input('__badName', 'String')],
            ),
          ],
        ),
      );
      expect(port.errors(schema), [
        'Name "__badName" must not begin with "__", which is '
            'reserved by GraphQL introspection.',
      ]);
    });
  });
}
