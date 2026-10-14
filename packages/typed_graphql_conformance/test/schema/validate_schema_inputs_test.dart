import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: input objects,
// their cycles and default values. Locations are compared as graphql-js reports
// them; mapping/schema.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Type System: Input Objects must have fields', () {
    test('accepts an Input Object type with fields', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        field: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Input Object type with missing fields', () {
      var schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject
    ''');
      schema = port.extend(schema, '''
        directive @test on INPUT_OBJECT

        extend input SomeInputObject @test
      ''');
      expect(port.errors(schema), [
        'Input Object type SomeInputObject must define one or more '
            'fields. @ 6:7',
      ]);
    });

    test('accepts an Input Object with breakable circular reference', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        self: SomeInputObject
        arrayOfSelf: [SomeInputObject]
        nonNullArrayOfSelf: [SomeInputObject]!
        nonNullArrayOfNonNullSelf: [SomeInputObject!]!
        intermediateSelf: AnotherInputObject
      }

      input AnotherInputObject {
        parent: SomeInputObject
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Input Object with non-breakable circular reference', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        nonNullSelf: SomeInputObject!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object SomeInputObject cannot be provided a finite value '
            'because it references itself through fields: '
            'SomeInputObject.nonNullSelf. @ 7:9',
      ]);
    });

    test('rejects Input Objects with non-breakable circular reference spread across them', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        startLoop: AnotherInputObject!
      }

      input AnotherInputObject {
        nextInLoop: YetAnotherInputObject!
      }

      input YetAnotherInputObject {
        closeLoop: SomeInputObject!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object SomeInputObject cannot be provided a finite value '
            'because it references itself through fields: '
            'SomeInputObject.startLoop, AnotherInputObject.nextInLoop, '
            'YetAnotherInputObject.closeLoop. @ 7:9 11:9 15:9',
      ]);
    });

    test(
      'rejects Input Objects with multiple non-breakable circular reference',
      () {
        final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        startLoop: AnotherInputObject!
      }

      input AnotherInputObject {
        closeLoop: SomeInputObject!
        startSecondLoop: YetAnotherInputObject!
      }

      input YetAnotherInputObject {
        closeSecondLoop: AnotherInputObject!
        nonNullSelf: YetAnotherInputObject!
      }
    ''');
        expect(port.errors(schema), [
          'Input Object SomeInputObject cannot be provided a finite value '
              'because it references itself through fields: '
              'SomeInputObject.startLoop, AnotherInputObject.closeLoop. @ 7:9 '
              '11:9',
          'Input Object AnotherInputObject cannot be provided a finite '
              'value because it references itself through fields: '
              'AnotherInputObject.startSecondLoop, '
              'YetAnotherInputObject.closeSecondLoop. @ 12:9 16:9',
          'Input Object YetAnotherInputObject cannot be provided a finite '
              'value because it references itself through fields: '
              'YetAnotherInputObject.nonNullSelf. @ 17:9',
        ]);
      },
    );

    test(
      'rejects an Input Object with multiple non-breakable circular references',
      () {
        final schema = port.build('''
      type Query {
        field(arg: A): String
      }

      input A {
        b: B!
        c: C!
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
      },
    );

    test('accepts Input Objects with default values without circular references (SDL)', () {
      final validSchema = port.build('''
      type Query {
        field(arg1: A, arg2: B): String
      }

      input A {
        x: A = null
        y: A = { x: null, y: null }
        z: [A] = []
      }

      input B {
        x: B2! = {}
        y: String = "abc"
        z: Custom = {}
      }

      input B2 {
        x: B3 = {}
      }

      input B3 {
        x: B = { x: { x: null } }
      }

      scalar Custom
    ''');
      expect(port.errors(validSchema), isEmpty);
    });

    test(
      'rejects Input Objects with default value circular reference (SDL)',
      () {
        final invalidSchema = port.build('''
      type Query {
        field(arg1: A, arg2: B, arg3: C, arg4: D, arg5: E): String
      }

      input A {
        x: A = {}
      }

      input B {
        x: B2 = {}
      }

      input B2 {
        x: B3 = {}
      }

      input B3 {
        x: B = {}
      }

      input C {
        x: [C] = [{}]
      }

      input D {
        x: D = { x: { x: {} } }
      }

      input E {
        x: E = { x: null }
        y: E = { y: null }
      }

      input F {
        x: F2! = {}
      }

      input F2 {
        x: F = { x: {} }
      }
    ''');
        expect(port.errors(invalidSchema), [
          'Invalid circular reference. The default value of Input Object '
              'field A.x references itself. @ 7:16',
          'Invalid circular reference. The default value of Input Object '
              'field B.x references itself via the default values of: B2.x, '
              'B3.x. @ 11:17 15:17 19:16',
          'Invalid circular reference. The default value of Input Object '
              'field C.x references itself. @ 23:18',
          'Invalid circular reference. The default value of Input Object '
              'field D.x references itself. @ 27:16',
          'Invalid circular reference. The default value of Input Object '
              'field E.x references itself via the default values of: E.y. @ '
              '31:16 32:16',
          'Invalid circular reference. The default value of Input Object '
              'field F2.x references itself. @ 40:16',
        ]);
      },
    );

    test('rejects an Input Object type with incorrectly typed fields', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      type SomeObject {
        field: String
      }

      union SomeUnion = SomeObject

      input SomeInputObject {
        badObject: SomeObject
        badUnion: SomeUnion
        goodInputObject: SomeInputObject
      }
    ''');
      expect(port.errors(schema), [
        'The type of SomeInputObject.badObject must be Input Type but '
            'got: SomeObject. @ 13:20',
        'The type of SomeInputObject.badUnion must be Input Type but '
            'got: SomeUnion. @ 14:19',
      ]);
    });

    test(
      'rejects an Input Object type with required field that is deprecated',
      () {
        final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        badField: String! @deprecated
        optionalField: String @deprecated
        anotherOptionalField: String! = "" @deprecated
      }
    ''');
        expect(port.errors(schema), [
          'Required input field SomeInputObject.badField cannot be '
              'deprecated. @ 7:27 7:19',
        ]);
      },
    );
  });

  group('Type System: Argument default values must be valid', () {
    test('rejects an argument with invalid default values (SDL)', () {
      final schema = port.build('''
      type Query {
        field(arg: Int = 3.14): Int
      }

      directive @bad(arg: Int = 2.718) on FIELD
    ''');
      expect(port.errors(schema), [
        '@bad(arg:) has invalid default value: Int cannot represent '
            'non-integer value: 2.718 @ 6:33',
        'Query.field(arg:) has invalid default value: Int cannot '
            'represent non-integer value: 3.14 @ 3:26',
      ]);
    });

    test('rejects an argument with invalid default values (programmatic)', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Query',
            fields: [
              SchemaField(
                'field',
                schemas.type('Int'),
                arguments: [schemas.input('arg', 'Int', defaultValue: '3.14')],
              ),
            ],
          ),
        ],
        directives: [
          SchemaDirective(
            'bad',
            arguments: [schemas.input('arg', 'Int', defaultValue: '2.718')],
            locations: [DirectiveLocation.field],
          ),
        ],
        queryTypeName: 'Query',
      );
      expect(port.errors(schema), [
        '@bad(arg:) has invalid default value: Int cannot represent non-integer '
            'value: 2.718',
        'Query.field(arg:) has invalid default value: Int cannot represent '
            'non-integer value: 3.14',
      ]);
    });
  });

  group('Type System: Input Object field default values must be valid', () {
    test('rejects an Input Object field with invalid default values (SDL)', () {
      final schema = port.build('''
    type Query {
      field(arg: SomeInputObject): Int
    }

    input SomeInputObject {
      field: Int = 3.14
    }
  ''');
      expect(port.errors(schema), [
        'SomeInputObject.field has invalid default value: Int cannot '
            'represent non-integer value: 3.14 @ 7:20',
      ]);
    });

    test('rejects an Input Object field with invalid default values (programmatic)', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Query',
            fields: [
              SchemaField(
                'field',
                schemas.type('Int'),
                arguments: [schemas.input('arg', 'SomeInputObject')],
              ),
            ],
          ),
          InputObjectType(
            'SomeInputObject',
            fields: [schemas.input('field', 'Int', defaultValue: '3.14')],
          ),
        ],
        queryTypeName: 'Query',
      );
      expect(port.errors(schema), [
        'SomeInputObject.field has invalid default value: Int cannot represent '
            'non-integer value: 3.14',
      ]);
    });
  });
}
