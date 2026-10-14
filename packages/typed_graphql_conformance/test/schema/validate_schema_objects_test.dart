import 'package:test/test.dart';

import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: objects
// implementing interfaces. Locations are compared as graphql-js reports them;
// mapping/schema.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();

  group('Objects must adhere to Interface they implement', () {
    test('accepts an Object which implements an Interface', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: String): String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test(
      'accepts an Object which implements an Interface along with more fields',
      () {
        final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: String): String
        anotherField: String
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('accepts an Object which implements an Interface field along with additional optional arguments', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: String, anotherInput: String): String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Object missing an Interface field', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        anotherField: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expected but '
            'AnotherObject does not provide it. @ 7:9 10:7',
      ]);
    });

    test('rejects an Object with an incorrectly typed Interface field', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: String): Int
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type String but '
            'AnotherObject.field is type Int. @ 7:31 11:31',
      ]);
    });

    test('rejects an Object with a differently typed Interface field', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      type A { foo: String }
      type B { foo: String }

      interface AnotherInterface {
        field: A
      }

      type AnotherObject implements AnotherInterface {
        field: B
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type A but '
            'AnotherObject.field is type B. @ 10:16 14:16',
      ]);
    });

    test('accepts an Object with a subtyped Interface field (interface)', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: AnotherInterface
      }

      type AnotherObject implements AnotherInterface {
        field: AnotherObject
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts an Object with a subtyped Interface field (union)', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      type SomeObject {
        field: String
      }

      union SomeUnionType = SomeObject

      interface AnotherInterface {
        field: SomeUnionType
      }

      type AnotherObject implements AnotherInterface {
        field: SomeObject
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Object missing an Interface argument', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field argument AnotherInterface.field(input:) '
            'expected but AnotherObject.field does not provide it. @ 7:15 '
            '11:9',
      ]);
    });

    test('rejects an Object with an incorrectly typed Interface argument', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: Int): String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field argument AnotherInterface.field(input:) expects '
            'type String but AnotherObject.field(input:) is type Int. @ 7:22 '
            '11:22',
      ]);
    });

    test(
      'rejects an Object with both an incorrectly typed field and argument',
      () {
        final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: Int): Int
      }
    ''');
        expect(port.errors(schema), [
          'Interface field AnotherInterface.field expects type String but '
              'AnotherObject.field is type Int. @ 7:31 11:28',
          'Interface field argument AnotherInterface.field(input:) expects '
              'type String but AnotherObject.field(input:) is type Int. @ 7:22 '
              '11:22',
        ]);
      },
    );

    test('rejects an Object which implements an Interface field along with additional required arguments', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(baseArg: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(
          baseArg: String,
          requiredArg: String!
          optionalArg1: String,
          optionalArg2: String = "",
        ): String
      }
    ''');
      expect(port.errors(schema), [
        'Argument "AnotherObject.field(requiredArg:)" must not be '
            'required type "String!" if not provided by the Interface field '
            '"AnotherInterface.field". @ 13:11 7:9',
      ]);
    });

    test(
      'accepts an Object with an equivalently wrapped Interface field type',
      () {
        final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: [String]!
      }

      type AnotherObject implements AnotherInterface {
        field: [String]!
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('rejects an Object with a non-list Interface field list type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: [String]
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type [String] '
            'but AnotherObject.field is type String. @ 7:16 11:16',
      ]);
    });

    test('rejects an Object with a list Interface field non-list type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: [String]
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type String but '
            'AnotherObject.field is type [String]. @ 7:16 11:16',
      ]);
    });

    test('accepts an Object with a subset non-null Interface field type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String!
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Object with a superset nullable Interface field type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String!
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type String! but '
            'AnotherObject.field is type String. @ 7:16 11:16',
      ]);
    });

    test('rejects an Object missing a transitive interface', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface SuperInterface {
        field: String!
      }

      interface AnotherInterface implements SuperInterface {
        field: String!
      }

      type AnotherObject implements AnotherInterface {
        field: String!
      }
    ''');
      expect(port.errors(schema), [
        'Type AnotherObject must implement SuperInterface because it is '
            'implemented by AnotherInterface. @ 10:45 14:37',
      ]);
    });
  });
}
