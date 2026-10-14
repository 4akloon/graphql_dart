import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: input and
// output types of fields and arguments, and implemented interfaces. Locations
// are compared as graphql-js reports them; mapping/schema.csv says which tests
// are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();
  List<String> withModifiersOf(List<String> names) => [
    for (final name in names) ...port.withModifiers(name),
  ];
  final outputTypes = withModifiersOf([
    'String',
    'SomeScalar',
    'SomeEnum',
    'SomeObject',
    'SomeUnion',
    'SomeInterface',
  ]);
  final notOutputTypes = withModifiersOf(['SomeInputObject']);
  final inputTypes = withModifiersOf([
    'String',
    'SomeScalar',
    'SomeEnum',
    'SomeInputObject',
  ]);
  final notInputTypes = withModifiersOf([
    'SomeObject',
    'SomeUnion',
    'SomeInterface',
  ]);

  group('Type System: Object fields must have output types', () {
    test('rejects with relevant locations for a non-output type as an Object field type', () {
      final schema = port.build('''
      type Query {
        field: [SomeInputObject]
      }

      input SomeInputObject {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'The type of Query.field must be Output Type but got: '
            '[SomeInputObject]. @ 3:16',
      ]);
    });

    Schema schemaWithObjectField(String type) => port.schema([
      ObjectType(
        'Query',
        fields: [SchemaField('f', schemas.type('BadObject'))],
      ),
      ObjectType(
        'BadObject',
        fields: [SchemaField('badField', schemas.type(type))],
      ),
      ...port.someTypes,
    ]);
    for (final type in outputTypes) {
      test('accepts an output type as an Object field type: $type', () {
        expect(port.errors(schemaWithObjectField(type)), isEmpty);
      });
    }
    for (final type in notOutputTypes) {
      test('rejects a non-output type as an Object field type: $type', () {
        expect(port.errors(schemaWithObjectField(type)), [
          'The type of BadObject.badField must be Output Type but got: $type.',
        ]);
      });
    }
  });

  group('Type System: Objects can only implement unique interfaces', () {
    test('rejects an Object implementing a non-Interface type', () {
      final schema = port.build('''
      type Query {
        test: BadObject
      }

      input SomeInputObject {
        field: String
      }

      type BadObject implements SomeInputObject {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type BadObject must only implement Interface types, it cannot '
            'implement SomeInputObject. @ 10:33',
      ]);
    });

    test('rejects an Object implementing the same interface twice', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface & AnotherInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type AnotherObject can only implement AnotherInterface once. @ '
            '10:37 10:56',
      ]);
    });

    test('rejects an Object implementing the same interface twice due to extension', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      final extendedSchema = schemas.extend(
        schema,
        'extend type AnotherObject implements AnotherInterface',
      );
      expect(port.errors(extendedSchema), [
        'Type AnotherObject can only implement AnotherInterface once. @ '
            '10:37 1:38',
      ]);
    });
  });

  group('Type System: Interface extensions should be valid', () {
    test('rejects an Object implementing the extended interface due to missing field', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      final extendedSchema = port.extend(schema, '''
        extend interface AnotherInterface {
          newField: String
        }

        extend type AnotherObject {
          differentNewField: String
        }
      ''');
      expect(port.errors(extendedSchema), [
        'Interface field AnotherInterface.newField expected but '
            'AnotherObject does not provide it. @ 3:11 10:7',
      ]);
    });

    test('rejects an Object implementing the extended interface due to missing field args', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      final extendedSchema = port.extend(schema, '''
        extend interface AnotherInterface {
          newField(test: Boolean): String
        }

        extend type AnotherObject {
          newField: String
        }
      ''');
      expect(port.errors(extendedSchema), [
        'Interface field argument AnotherInterface.newField(test:) '
            'expected but AnotherObject.newField does not provide it. @ 3:20 '
            '7:11',
      ]);
    });

    test('rejects Objects implementing the extended interface due to mismatching interface type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      final extendedSchema = port.extend(schema, '''
        extend interface AnotherInterface {
          newInterfaceField: NewInterface
        }

        interface NewInterface {
          newField: String
        }

        interface MismatchingInterface {
          newField: String
        }

        extend type AnotherObject {
          newInterfaceField: MismatchingInterface
        }

        # Required to prevent unused interface errors
        type DummyObject implements NewInterface & MismatchingInterface {
          newField: String
        }
      ''');
      expect(port.errors(extendedSchema), [
        'Interface field AnotherInterface.newInterfaceField expects type '
            'NewInterface but AnotherObject.newInterfaceField is type '
            'MismatchingInterface. @ 3:30 15:30',
      ]);
    });
  });

  group('Type System: Interface fields must have output types', () {
    test(
      'rejects a non-output type as an Interface field type with locations',
      () {
        final schema = port.build('''
      type Query {
        test: SomeInterface
      }

      interface SomeInterface {
        field: SomeInputObject
      }

      input SomeInputObject {
        foo: String
      }

      type SomeObject implements SomeInterface {
        field: SomeInputObject
      }
    ''');
        expect(port.errors(schema), [
          'The type of SomeInterface.field must be Output Type but got: '
              'SomeInputObject. @ 7:16',
          'The type of SomeObject.field must be Output Type but got: '
              'SomeInputObject. @ 15:16',
        ]);
      },
    );

    test('accepts an interface not implemented by at least one object', () {
      final schema = port.build('''
      type Query {
        test: SomeInterface
      }

      interface SomeInterface {
        foo: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    // BadImplementing comes first, as in graphql-js's type map.
    Schema schemaWithInterfaceField(String type) {
      final fields = [SchemaField('badField', schemas.type(type))];
      return port.schema([
        ObjectType(
          'BadImplementing',
          interfaces: [const NamedTypeReference('BadInterface')],
          fields: fields,
        ),
        InterfaceType('BadInterface', fields: fields),
        ObjectType(
          'Query',
          fields: [SchemaField('f', schemas.type('BadInterface'))],
        ),
        ...port.someTypes,
      ]);
    }

    for (final type in outputTypes) {
      test('accepts an output type as an Interface field type: $type', () {
        expect(port.errors(schemaWithInterfaceField(type)), isEmpty);
      });
    }
    for (final type in notOutputTypes) {
      test('rejects a non-output type as an Interface field type: $type', () {
        expect(port.errors(schemaWithInterfaceField(type)), [
          'The type of BadImplementing.badField must be Output Type but got: '
              '$type.',
          'The type of BadInterface.badField must be Output Type but got: '
              '$type.',
        ]);
      });
    }
  });

  group('Type System: Arguments must have input types', () {
    test('rejects a required argument that is deprecated', () {
      final schema = port.build('''
      directive @BadDirective(
        badArg: String! @deprecated
        optionalArg: String @deprecated
        anotherOptionalArg: String! = "" @deprecated
      ) on FIELD

      type Query {
        test(
          badArg: String! @deprecated
          optionalArg: String @deprecated
          anotherOptionalArg: String! = "" @deprecated
        ): String
      }
    ''');
      expect(port.errors(schema), [
        'Required argument @BadDirective(badArg:) cannot be deprecated. '
            '@ 3:25 3:17',
        'Required argument Query.test(badArg:) cannot be deprecated. @ '
            '10:27 10:19',
      ]);
    });

    test('rejects a non-input type as a field arg with locations', () {
      final schema = port.build('''
      type Query {
        test(arg: SomeObject): String
      }

      type SomeObject {
        foo: String
      }
    ''');
      expect(port.errors(schema), [
        'The type of Query.test(arg:) must be Input Type but got: '
            'SomeObject. @ 3:19',
      ]);
    });

    Schema schemaWithArg(String type) => port.schema(
      [
        ObjectType(
          'Query',
          fields: [SchemaField('f', schemas.type('BadObject'))],
        ),
        ObjectType(
          'BadObject',
          fields: [
            SchemaField(
              'badField',
              schemas.type('String'),
              arguments: [schemas.input('badArg', type)],
            ),
          ],
        ),
        ...port.someTypes,
      ],
      directives: [
        SchemaDirective(
          'BadDirective',
          arguments: [schemas.input('badArg', type)],
          locations: [DirectiveLocation.query],
        ),
      ],
    );
    for (final type in inputTypes) {
      test('accepts an input type as a field arg type: $type', () {
        expect(port.errors(schemaWithArg(type)), isEmpty);
      });
    }
    for (final type in notInputTypes) {
      test('rejects a non-input type as a field arg type: $type', () {
        expect(port.errors(schemaWithArg(type)), [
          'The type of @BadDirective(badArg:) must be Input Type but got: '
              '$type.',
          'The type of BadObject.badField(badArg:) must be Input Type but got: '
              '$type.',
        ]);
      });
    }
  });

  group('Type System: Input Object fields must have input types', () {
    test(
      'rejects a non-input type as an input object field with locations',
      () {
        final schema = port.build('''
      type Query {
        test(arg: SomeInputObject): String
      }

      input SomeInputObject {
        foo: SomeObject
      }

      type SomeObject {
        bar: String
      }
    ''');
        expect(port.errors(schema), [
          'The type of SomeInputObject.foo must be Input Type but got: '
              'SomeObject. @ 7:14',
        ]);
      },
    );

    Schema schemaWithInputField(String type) => port.schema([
      ObjectType(
        'Query',
        fields: [
          SchemaField(
            'f',
            schemas.type('String'),
            arguments: [schemas.input('badArg', 'BadInputObject')],
          ),
        ],
      ),
      InputObjectType(
        'BadInputObject',
        fields: [schemas.input('badField', type)],
      ),
      ...port.someTypes,
    ]);
    for (final type in inputTypes) {
      test('accepts an input type as an input field type: $type', () {
        expect(port.errors(schemaWithInputField(type)), isEmpty);
      });
    }
    for (final type in notInputTypes) {
      test('rejects a non-input type as an input field type: $type', () {
        expect(port.errors(schemaWithInputField(type)), [
          'The type of BadInputObject.badField must be Input Type but got: '
              '$type.',
        ]);
      });
    }
  });
}
