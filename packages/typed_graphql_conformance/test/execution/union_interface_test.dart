import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

class _Dog {
  _Dog(this.name, this.barks);

  final String name;
  final bool barks;
  _Dog? mother;
  _Dog? father;
  List<_Dog> progeny = [];
}

class _Cat {
  _Cat(this.name, this.meows);

  final String name;
  final bool meows;
  _Cat? mother;
  _Cat? father;
  List<_Cat> progeny = [];
}

class _Plant {
  _Plant(this.name);

  final String name;
}

class _Person {
  _Person(this.name, [this.pets, this.friends, this.responsibilities]);

  final String name;
  final List<Object>? pets;
  final List<Object>? friends;
  final List<Object>? responsibilities;
  _Person? mother;
  _Person? father;
  List<_Person> progeny = [];
}

// Ported from graphql-js src/execution/__tests__/union-interface-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  late final InterfaceTypeDef<Object?> life;
  late final InterfaceTypeDef<Object?> mammal;
  late final ObjectTypeDef<_Dog> dog;
  late final ObjectTypeDef<_Cat> cat;
  late final ObjectTypeDef<_Person> person;
  final named = b.interface<Object?>(
    'Named',
    fields: (t) => [t.field('name', b.string.nullable).declareOnly()],
  );
  life = b.interface<Object?>(
    'Life',
    fields: (t) => [
      t.field('progeny', b.list(life.nullable).nullable).declareOnly(),
    ],
  );
  mammal = b.interface<Object?>(
    'Mammal',
    interfaces: [life],
    fields: (t) => [
      t.field('progeny', b.list(mammal.nullable).nullable).declareOnly(),
      t.field('mother', mammal.nullable).declareOnly(),
      t.field('father', mammal.nullable).declareOnly(),
    ],
  );
  dog = b.object<_Dog>(
    'Dog',
    interfaces: [mammal, life, named],
    options: ObjectOptions(isTypeOf: (value) => value is _Dog),
    fields: (t) => [
      t.field('name', b.string.nullable).pure((d) => d.name),
      t.field('barks', b.boolean.nullable).pure((d) => d.barks),
      t.field('progeny', b.list(dog.nullable).nullable).pure((d) => d.progeny),
      t.field('mother', dog.nullable).pure((d) => d.mother),
      t.field('father', dog.nullable).pure((d) => d.father),
    ],
  );
  cat = b.object<_Cat>(
    'Cat',
    interfaces: [mammal, life, named],
    options: ObjectOptions(isTypeOf: (value) => value is _Cat),
    fields: (t) => [
      t.field('name', b.string.nullable).pure((c) => c.name),
      t.field('meows', b.boolean.nullable).pure((c) => c.meows),
      t.field('progeny', b.list(cat.nullable).nullable).pure((c) => c.progeny),
      t.field('mother', cat.nullable).pure((c) => c.mother),
      t.field('father', cat.nullable).pure((c) => c.father),
    ],
  );
  final plant = b.object<_Plant>(
    'Plant',
    interfaces: [named],
    options: ObjectOptions(isTypeOf: (value) => value is _Plant),
    fields: (t) => [t.field('name', b.string.nullable).pure((p) => p.name)],
  );
  final pet = b.union<Object?>(
    'Pet',
    members: [dog, cat],
    resolveType: (value) => value is _Dog ? dog : cat,
  );
  final petOrPlant = b.union<Object?>(
    'PetOrPlantType',
    members: [plant, dog, cat],
  );
  person = b.object<_Person>(
    'Person',
    interfaces: [named, mammal, life],
    options: ObjectOptions(isTypeOf: (value) => value is _Person),
    fields: (t) => [
      t.field('name', b.string.nullable).pure((p) => p.name),
      t.field('pets', b.list(pet.nullable).nullable).pure((p) => p.pets),
      t
          .field('friends', b.list(named.nullable).nullable)
          .pure((p) => p.friends),
      t
          .field('responsibilities', b.list(petOrPlant.nullable).nullable)
          .pure((p) => p.responsibilities),
      t
          .field('progeny', b.list(person.nullable).nullable)
          .pure((p) => p.progeny),
      t.field('mother', person.nullable).pure((p) => p.mother),
      t.field('father', person.nullable).pure((p) => p.father),
    ],
  );
  final schema = b.build(query: person);

  final garfield = _Cat('Garfield', false);
  garfield.mother = _Cat("Garfield's Mom", false);
  garfield.mother!.progeny = [garfield];
  final odie = _Dog('Odie', true);
  odie.mother = _Dog("Odie's Mom", true);
  odie.mother!.progeny = [odie];
  final fern = _Plant('Fern');
  final liz = _Person('Liz');
  final john = _Person('John', [garfield, odie], [liz, odie], [garfield, fern]);

  Future<Map<String, Object?>> run(String query, {Object? rootValue}) =>
      port.json(
        schema,
        query,
        options: ExecutionOptions(rootValue: rootValue, maskErrors: false),
      );

  final garfieldAndOdie = <Map<String, Object?>>[
    {'__typename': 'Cat', 'name': 'Garfield', 'meows': false},
    {'__typename': 'Dog', 'name': 'Odie', 'barks': true},
  ];
  final lizAndOdie = <Map<String, Object?>>[
    {'__typename': 'Person', 'name': 'Liz'},
    {'__typename': 'Dog', 'name': 'Odie', 'barks': true},
  ];

  group('Execute: Union and intersection types', () {
    test('executes using union types', () async {
      expect(
        await run('''
      {
        __typename
        name
        pets {
          __typename
          name
          barks
          meows
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'pets': garfieldAndOdie,
          },
        },
      );
    });

    test('executes union types with inline fragments', () async {
      expect(
        await run('''
      {
        __typename
        name
        pets {
          __typename
          ... on Dog {
            name
            barks
          }
          ... on Cat {
            name
            meows
          }
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'pets': garfieldAndOdie,
          },
        },
      );
    });

    test('executes using interface types', () async {
      expect(
        await run('''
      {
        __typename
        name
        friends {
          __typename
          name
          barks
          meows
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'friends': lizAndOdie,
          },
        },
      );
    });

    test('executes interface types with inline fragments', () async {
      expect(
        await run('''
      {
        __typename
        name
        friends {
          __typename
          name
          ... on Dog {
            barks
          }
          ... on Cat {
            meows
          }

          ... on Mammal {
            mother {
              __typename
              ... on Dog {
                name
                barks
              }
              ... on Cat {
                name
                meows
              }
            }
          }
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'friends': [
              {'__typename': 'Person', 'name': 'Liz', 'mother': null},
              {
                '__typename': 'Dog',
                'name': 'Odie',
                'barks': true,
                'mother': {
                  '__typename': 'Dog',
                  'name': "Odie's Mom",
                  'barks': true,
                },
              },
            ],
          },
        },
      );
    });

    test('executes interface types with named fragments', () async {
      expect(
        await run('''
      {
        __typename
        name
        friends {
          __typename
          name
          ...DogBarks
          ...CatMeows
        }
      }

      fragment  DogBarks on Dog {
        barks
      }

      fragment  CatMeows on Cat {
        meows
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'friends': lizAndOdie,
          },
        },
      );
    });

    test('allows fragment conditions to be abstract types', () async {
      expect(
        await run('''
      {
        __typename
        name
        pets {
          ...PetFields,
          ...on Mammal {
            mother {
              ...ProgenyFields
            }
          }
        }
        friends { ...FriendFields }
      }

      fragment PetFields on Pet {
        __typename
        ... on Dog {
          name
          barks
        }
        ... on Cat {
          name
          meows
        }
      }

      fragment FriendFields on Named {
        __typename
        name
        ... on Dog {
          barks
        }
        ... on Cat {
          meows
        }
      }

      fragment ProgenyFields on Life {
        progeny {
          __typename
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'pets': [
              {
                '__typename': 'Cat',
                'name': 'Garfield',
                'meows': false,
                'mother': {
                  'progeny': [
                    {'__typename': 'Cat'},
                  ],
                },
              },
              {
                '__typename': 'Dog',
                'name': 'Odie',
                'barks': true,
                'mother': {
                  'progeny': [
                    {'__typename': 'Dog'},
                  ],
                },
              },
            ],
            'friends': lizAndOdie,
          },
        },
      );
    });
  });
}
