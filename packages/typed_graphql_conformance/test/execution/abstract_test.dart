import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

class _Dog {
  _Dog(this.name, this.woofs);

  final String name;
  final bool woofs;
}

class _Cat {
  _Cat(this.name, this.meows);

  final String name;
  final bool meows;
}

typedef _Source = Map<String, Object?>;

const _petsQuery = '''

      {
        pets {
          name
          ... on Dog {
            woofs
          }
          ... on Cat {
            meows
          }
        }
      }
    ''';

const _petQuery = '''

      {
        pet {
          name
        }
      }
    ''';

const _unresolvedMessage =
    'Abstract type "Pet" must resolve to an Object type at runtime for field '
    '"Query.pet". Either the "Pet" type should provide a "resolveType" '
    'function or each possible type should provide an "isTypeOf" function.';

// Ported from graphql-js src/execution/__tests__/abstract-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final odieAndGarfield = <Map<String, Object?>>[
    {'name': 'Odie', 'woofs': true},
    {'name': 'Garfield', 'meows': false},
  ];
  final bothFailed = <String, Object?>{
    'data': {
      'pets': [null, null],
    },
    'errors': [
      for (final index in [0, 1])
        {
          'message': 'We are testing this error',
          'locations': [
            {'line': 3, 'column': 9},
          ],
          'path': ['pets', index],
        },
    ],
  };
  Map<String, Object?> petFailure(String message) => {
    'data': {'pet': null},
    'errors': [
      {
        'message': message,
        'locations': [
          {'line': 3, 'column': 9},
        ],
        'path': ['pet'],
      },
    ],
  };

  // Query.pets: [Pet] over a Dog and a Cat.
  ExecutableSchema<Object?> petsSchema(
    ExecutableSchemaBuilder<Object?> b,
    OutputRef<Object?> pet,
  ) => b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('pets', b.list(pet.nullable).nullable)
            .pure(
              (_) => <Object>[_Dog('Odie', true), _Cat('Garfield', false)],
            ),
      ],
    ),
  );

  FieldDef<_Dog, Object?> dogName(
    ExecutableSchemaBuilder<Object?> b,
    FieldsBuilder<_Dog, Object?> t,
  ) => t.field('name', b.string.nullable).pure((dog) => dog.name);

  FieldDef<_Cat, Object?> catName(
    ExecutableSchemaBuilder<Object?> b,
    FieldsBuilder<_Cat, Object?> t,
  ) => t.field('name', b.string.nullable).pure((cat) => cat.name);

  List<FieldDef<_Dog, Object?>> dogFields(
    ExecutableSchemaBuilder<Object?> b,
    FieldsBuilder<_Dog, Object?> t,
  ) => [
    dogName(b, t),
    t.field('woofs', b.boolean.nullable).pure((dog) => dog.woofs),
  ];

  List<FieldDef<_Cat, Object?>> catFields(
    ExecutableSchemaBuilder<Object?> b,
    FieldsBuilder<_Cat, Object?> t,
  ) => [
    catName(b, t),
    t.field('meows', b.boolean.nullable).pure((cat) => cat.meows),
  ];

  InterfaceTypeDef<Object?> petInterface(
    ExecutableSchemaBuilder<Object?> b, {
    ObjectTypeDef<Object?> Function(Object? value)? resolveType,
  }) => b.interface<Object?>(
    'Pet',
    resolveType: resolveType,
    fields: (t) => [t.field('name', b.string.nullable).declareOnly()],
  );

  group('Execute: Handles execution of abstract types', () {
    test('isTypeOf used to resolve runtime type for Interface', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(b);
      b.object<_Dog>(
        'Dog',
        interfaces: [pet],
        options: ObjectOptions(isTypeOf: (value) => value is _Dog),
        fields: (t) => dogFields(b, t),
      );
      b.object<_Cat>(
        'Cat',
        interfaces: [pet],
        options: ObjectOptions(isTypeOf: (value) => value is _Cat),
        fields: (t) => catFields(b, t),
      );

      expect(await port.json(petsSchema(b, pet), _petsQuery), {
        'data': {'pets': odieAndGarfield},
      });
    });

    test('isTypeOf can throw', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(b);
      b.object<_Dog>(
        'Dog',
        interfaces: [pet],
        options: ObjectOptions(
          isTypeOf: (value) {
            throw const GraphQLException('We are testing this error');
          },
        ),
        fields: (t) => dogFields(b, t),
      );
      b.object<_Cat>(
        'Cat',
        interfaces: [pet],
        fields: (t) => catFields(b, t),
      );

      expect(await port.json(petsSchema(b, pet), _petsQuery), bothFailed);
    });

    test('isTypeOf can return false', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(b);
      b.object<_Dog>(
        'Dog',
        interfaces: [pet],
        options: ObjectOptions(isTypeOf: (value) => false),
        fields: (t) => dogFields(b, t),
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [t.field('pet', pet.nullable).pure((_) => Object())],
        ),
      );

      expect(
        await port.json(schema, _petQuery),
        petFailure(_unresolvedMessage),
      );
    });

    test('isTypeOf used to resolve runtime type for Union', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final dog = b.object<_Dog>(
        'Dog',
        options: ObjectOptions(isTypeOf: (value) => value is _Dog),
        fields: (t) => dogFields(b, t),
      );
      final cat = b.object<_Cat>(
        'Cat',
        options: ObjectOptions(isTypeOf: (value) => value is _Cat),
        fields: (t) => catFields(b, t),
      );
      final pet = b.union<Object?>('Pet', members: [dog, cat]);

      expect(
        await port.json(petsSchema(b, pet), '''
{
      pets {
        ... on Dog {
          name
          woofs
        }
        ... on Cat {
          name
          meows
        }
      }
    }'''),
        {
          'data': {'pets': odieAndGarfield},
        },
      );
    });

    test('resolveType can throw', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(
        b,
        resolveType: (value) {
          throw const GraphQLException('We are testing this error');
        },
      );
      b.object<_Dog>(
        'Dog',
        interfaces: [pet],
        fields: (t) => dogFields(b, t),
      );
      b.object<_Cat>(
        'Cat',
        interfaces: [pet],
        fields: (t) => catFields(b, t),
      );

      expect(await port.json(petsSchema(b, pet), _petsQuery), bothFailed);
    });

    // The two __typename tests share their sources and differ in the type.
    ExecutableSchema<Object?> typenameSchema(
      ExecutableSchemaBuilder<Object?> b, {
      required bool isUnion,
    }) {
      late final ObjectTypeDef<_Source> cat;
      late final ObjectTypeDef<_Source> dog;
      ObjectTypeDef<Object?> pick(_Source m) =>
          m['__typename'] == 'Dog' ? dog : cat;
      void declareMembers(List<InterfaceTypeDef<Object?>> interfaces) {
        cat = b.object<_Source>(
          'Cat',
          interfaces: interfaces,
          fields: (t) => [
            t
                .field('name', b.string.nullable)
                .pure((m) => m['name'] as String?),
            t
                .field('meows', b.boolean.nullable)
                .pure((m) => m['meows'] as bool?),
          ],
        );
        dog = b.object<_Source>(
          'Dog',
          interfaces: interfaces,
          fields: (t) => [
            t
                .field('name', b.string.nullable)
                .pure((m) => m['name'] as String?),
            t
                .field('woofs', b.boolean.nullable)
                .pure((m) => m['woofs'] as bool?),
          ],
        );
      }

      final OutputRef<_Source> pet;
      if (isUnion) {
        declareMembers([]);
        pet = b.union<_Source>('Pet', members: [cat, dog], resolveType: pick);
      } else {
        final interface = b.interface<_Source>(
          'Pet',
          resolveType: pick,
          fields: (t) => [t.field('name', b.string.nullable).declareOnly()],
        );
        declareMembers([interface]);
        pet = interface;
      }
      return b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field('pets', b.list(pet.nullable).nullable)
                .pure(
                  (_) => <_Source>[
                    {'__typename': 'Dog', 'name': 'Odie', 'woofs': true},
                    {'__typename': 'Cat', 'name': 'Garfield', 'meows': false},
                  ],
                ),
          ],
        ),
      );
    }

    test('resolve Union type using __typename on source object', () async {
      final schema = typenameSchema(
        ExecutableSchemaBuilder<Object?>(),
        isUnion: true,
      );

      expect(await port.json(schema, _petsQuery), {
        'data': {'pets': odieAndGarfield},
      });
    });

    test('resolve Interface type using __typename on source object', () async {
      final schema = typenameSchema(
        ExecutableSchemaBuilder<Object?>(),
        isUnion: false,
      );

      expect(await port.json(schema, _petsQuery), {
        'data': {'pets': odieAndGarfield},
      });
    });

    test('resolveType on Interface yields useful error', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(b);
      b.object<_Cat>('Cat', interfaces: [pet], fields: (t) => [catName(b, t)]);
      b.object<_Dog>('Dog', interfaces: [pet], fields: (t) => [dogName(b, t)]);
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [t.field('pet', pet.nullable).pure((_) => Object())],
        ),
      );
      expect(
        await port.json(schema, _petQuery),
        petFailure(_unresolvedMessage),
      );

      final other = ExecutableSchemaBuilder<Object?>();
      late final ObjectTypeDef<_Dog> human;
      final otherPet = petInterface(other, resolveType: (value) => human);
      other.object<_Cat>(
        'Cat',
        interfaces: [otherPet],
        fields: (t) => [catName(other, t)],
      );
      human = other.object<_Dog>('Human', fields: (t) => [dogName(other, t)]);
      final otherSchema = other.build(
        query: other.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('pet', otherPet.nullable).pure((_) => _Dog('Rex', true)),
          ],
        ),
      );
      expect(
        await port.json(otherSchema, _petQuery),
        petFailure(
          'Runtime Object type "Human" is not a possible type for "Pet".',
        ),
      );
    });
  });
}
