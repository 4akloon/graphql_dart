import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: interfaces
// implementing interfaces, and assertValidSchema. Locations are compared as
// graphql-js reports them; mapping/schema.csv says which tests are adapted or
// skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Interfaces must adhere to Interface they implement', () {
    test('accepts an Interface which implements an Interface', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: String): String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts an Interface which implements an Interface along with more fields', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: String): String
        anotherField: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts an Interface which implements an Interface field along with additional optional arguments', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: String, anotherInput: String): String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Interface missing an Interface field', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        anotherField: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expected but '
            'ChildInterface does not provide it. @ 7:9 10:7',
      ]);
    });

    test('rejects an Interface with an incorrectly typed Interface field', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: String): Int
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expects type String but '
            'ChildInterface.field is type Int. @ 7:31 11:31',
      ]);
    });

    test('rejects an Interface with a differently typed Interface field', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      type A { foo: String }
      type B { foo: String }

      interface ParentInterface {
        field: A
      }

      interface ChildInterface implements ParentInterface {
        field: B
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expects type A but '
            'ChildInterface.field is type B. @ 10:16 14:16',
      ]);
    });

    test(
      'accepts an Interface with a subtyped Interface field (interface)',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: ParentInterface
      }

      interface ChildInterface implements ParentInterface {
        field: ChildInterface
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('accepts an Interface with a subtyped Interface field (union)', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      type SomeObject {
        field: String
      }

      union SomeUnionType = SomeObject

      interface ParentInterface {
        field: SomeUnionType
      }

      interface ChildInterface implements ParentInterface {
        field: SomeObject
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Interface implementing a non-Interface type', () {
      final schema = port.build('''
      type Query {
        field: String
      }

      input SomeInputObject {
        field: String
      }

      interface BadInterface implements SomeInputObject {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type BadInterface must only implement Interface types, it '
            'cannot implement SomeInputObject. @ 10:41',
      ]);
    });

    test('rejects an Interface missing an Interface argument', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field argument ParentInterface.field(input:) expected '
            'but ChildInterface.field does not provide it. @ 7:15 11:9',
      ]);
    });

    test(
      'rejects an Interface with an incorrectly typed Interface argument',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: Int): String
      }
    ''');
        expect(port.errors(schema), [
          'Interface field argument ParentInterface.field(input:) expects '
              'type String but ChildInterface.field(input:) is type Int. @ '
              '7:22 11:22',
        ]);
      },
    );

    test(
      'rejects an Interface with both an incorrectly typed field and argument',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: Int): Int
      }
    ''');
        expect(port.errors(schema), [
          'Interface field ParentInterface.field expects type String but '
              'ChildInterface.field is type Int. @ 7:31 11:28',
          'Interface field argument ParentInterface.field(input:) expects '
              'type String but ChildInterface.field(input:) is type Int. @ '
              '7:22 11:22',
        ]);
      },
    );

    test('rejects an Interface which implements an Interface field along with additional required arguments', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(baseArg: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(
          baseArg: String,
          requiredArg: String!
          optionalArg1: String,
          optionalArg2: String = "",
        ): String
      }
    ''');
      expect(port.errors(schema), [
        'Argument "ChildInterface.field(requiredArg:)" must not be '
            'required type "String!" if not provided by the Interface field '
            '"ParentInterface.field". @ 13:11 7:9',
      ]);
    });

    test(
      'accepts an Interface with an equivalently wrapped Interface field type',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: [String]!
      }

      interface ChildInterface implements ParentInterface {
        field: [String]!
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('rejects an Interface with a non-list Interface field list type', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: [String]
      }

      interface ChildInterface implements ParentInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expects type [String] but '
            'ChildInterface.field is type String. @ 7:16 11:16',
      ]);
    });

    test('rejects an Interface with a list Interface field non-list type', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: String
      }

      interface ChildInterface implements ParentInterface {
        field: [String]
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expects type String but '
            'ChildInterface.field is type [String]. @ 7:16 11:16',
      ]);
    });

    test(
      'accepts an Interface with a subset non-null Interface field type',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: String
      }

      interface ChildInterface implements ParentInterface {
        field: String!
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test(
      'rejects an Interface with a superset nullable Interface field type',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: String!
      }

      interface ChildInterface implements ParentInterface {
        field: String
      }
    ''');
        expect(port.errors(schema), [
          'Interface field ParentInterface.field expects type String! but '
              'ChildInterface.field is type String. @ 7:16 11:16',
        ]);
      },
    );

    test('rejects an Object missing a transitive interface', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface SuperInterface {
        field: String!
      }

      interface ParentInterface implements SuperInterface {
        field: String!
      }

      interface ChildInterface implements ParentInterface {
        field: String!
      }
    ''');
      expect(port.errors(schema), [
        'Type ChildInterface must implement SuperInterface because it is '
            'implemented by ParentInterface. @ 10:44 14:43',
      ]);
    });

    test('rejects a self reference interface', () {
      final schema = port.build('''
      type Query {
        test: FooInterface
      }

      interface FooInterface implements FooInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type FooInterface cannot implement itself because it would '
            'create a circular reference. @ 6:41',
      ]);
    });

    test('rejects a circular Interface implementation', () {
      final schema = port.build('''
      type Query {
        test: FooInterface
      }

      interface FooInterface implements BarInterface {
        field: String
      }

      interface BarInterface implements FooInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type FooInterface cannot implement BarInterface because it '
            'would create a circular reference. @ 10:41 6:41',
        'Type BarInterface cannot implement FooInterface because it '
            'would create a circular reference. @ 6:41 10:41',
      ]);
    });

    test('rejects deprecated implementation field when interface field is not deprecated', () {
      final schema = port.build('''
      interface Node {
        id: ID!
      }

      type Foo implements Node {
        id: ID! @deprecated
      }

      type Query {
        foo: Foo
      }
    ''');
      expect(port.errors(schema), [
        'Interface field Node.id is not deprecated, so implementation '
            'field Foo.id must not be deprecated. @ 7:17 7:13',
      ]);
    });
  });

  group('assertValidSchema', () {
    test('does not throw on valid schemas', () {
      final schema = port.build('''
      type Query {
        foo: String
      }
    ''');
      expect(const SchemaValidator().validate(schema), isA<ValidSchema>());
    });

    test('combines multiple errors', () {
      final schema = schemas.build('type SomeType');
      expect(port.errors(schema), [
        'Query root type must be provided.',
        'Type SomeType must define one or more fields. @ 1:1',
      ]);
    });
  });
}
