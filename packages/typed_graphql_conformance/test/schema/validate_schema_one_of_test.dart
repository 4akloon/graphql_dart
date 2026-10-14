import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: OneOf input
// objects. Locations are compared as graphql-js reports them;
// mapping/schema.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Type System: OneOf Input Object fields must be nullable', () {
    test('accepts a OneOf Input Object with a scalar field', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        a: Int
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a OneOf Input Object with a recursive list field', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        a: [A!]
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test(
      'accepts a OneOf Input Object referencing a non-OneOf input object',
      () {
        final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
      }

      input B {
        x: Int
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('accepts a OneOf Input Object referencing an already checked input object', () {
      final schema = port.build('''
      type Query {
        a(arg: A): Int
      }

      input B {
        value: Int
      }

      input A @oneOf {
        b: B
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test(
      'accepts a OneOf Input Object with multiple acyclic input object fields',
      () {
        final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
        c: C
      }

      input B {
        value: Int
      }

      input C {
        value: Int
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('accepts a OneOf/OneOf cycle with a scalar escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
        escape: Int
      }

      input B @oneOf {
        a: A
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a OneOf/non-OneOf cycle with a nullable escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
      }

      input B {
        a: A
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a OneOf/non-OneOf with scalar escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
        escape: Int
      }

      input B {
        a: A!
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a non-OneOf/non-OneOf cycle with a nullable escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A {
        b: B!
      }

      input B {
        a: A
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a non-OneOf/non-OneOf cycle with a non-null list of non-null items escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A {
        b: [B!]!
      }

      input B {
        a: A!
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects non-nullable fields', () {
      final schema = port.build('''
      type Query {
        test(arg: SomeInputObject): String
      }

      input SomeInputObject @oneOf {
        a: String
        b: String!
      }
    ''');
      expect(port.errors(schema), [
        'OneOf input field SomeInputObject.b must be nullable. @ 8:12',
      ]);
    });

    test('rejects fields with default values', () {
      final schema = port.build('''
      type Query {
        test(arg: SomeInputObject): String
      }

      input SomeInputObject @oneOf {
        a: String
        b: String = "foo"
      }
    ''');
      expect(port.errors(schema), [
        'OneOf input field SomeInputObject.b cannot have a default '
            'value. @ 8:9',
      ]);
    });

    test('rejects a self-referencing OneOf type with no escapes', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        self: A
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.self. @ 7:9',
      ]);
    });

    test(
      'rejects a non-OneOf Input Object requiring an unbreakable OneOf cycle',
      () {
        final schema = port.build('''
      type Query {
        a(arg: A): Int
      }

      input T @oneOf {
        self: T
      }

      input A {
        t: T!
      }
    ''');
        expect(port.errors(schema), [
          'Input Object T cannot be provided a finite value because it '
              'references itself through fields: T.self. @ 7:9',
        ]);
      },
    );

    test('checks each shared unbreakable OneOf subgraph once', () {
      const chainLength = 16;
      final oneOf = schemas.applied('@oneOf');
      final types = [
        InputObjectType(
          'T0',
          appliedDirectives: oneOf,
          fields: [schemas.input('self', 'T0')],
        ),
        for (var i = 1; i <= chainLength; i++)
          InputObjectType(
            'T$i',
            appliedDirectives: oneOf,
            fields: [
              schemas.input('a', 'T${i - 1}'),
              schemas.input('b', 'T${i - 1}'),
            ],
          ),
      ];
      final schema = Schema(
        types: [
          ObjectType(
            'Query',
            fields: [
              SchemaField(
                'test',
                schemas.type('Int'),
                arguments: [schemas.input('input', 'T$chainLength')],
              ),
            ],
          ),
          ...types,
        ],
        queryTypeName: 'Query',
      );
      expect(port.errors(schema), hasLength(1));
    });

    test('rejects a mixed OneOf/non-OneOf cycle with no escapes', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
      }

      input B {
        a: A!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.b, B.a. @ 7:9 11:9',
      ]);
    });

    test('rejects multiple OneOf branches without duplicate cycle reports', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
        c: C
      }

      input B {
        a: A!
      }

      input C {
        a: A!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.b, B.a. @ 7:9 12:9',
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.c, C.a. @ 8:9 16:9',
      ]);
    });

    test('rejects a non-OneOf/non-OneOf cycle with required scalar, list, and finite input fields', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A {
        list: [B]!
        finite: Finite!
        b: B!
      }

      input B {
        value: Int!
        a: A!
      }

      input Finite {
        value: Int!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.b, B.a. @ 9:9 14:9',
      ]);
    });

    test('rejects a larger mixed OneOf/non-OneOf cycle with no escapes', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
      }

      input B {
        c: C!
      }

      input C @oneOf {
        a: A
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.b, B.c, C.a. @ 7:9 11:9 15:9',
      ]);
    });
  });
}
