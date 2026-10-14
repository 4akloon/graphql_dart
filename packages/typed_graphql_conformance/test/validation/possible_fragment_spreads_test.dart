import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/PossibleFragmentSpreadsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const PossibleFragmentSpreadsRule()).withSchema('''
  interface Being {
    name: String
  }

  interface Pet implements Being {
    name: String
  }

  type Dog implements Being & Pet {
    name: String
    barkVolume: Int
  }

  type Cat implements Being & Pet {
    name: String
    meowVolume: Int
  }

  union CatOrDog = Cat | Dog

  interface Intelligent {
    iq: Int
  }

  type Human implements Being & Intelligent {
    name: String
    pets: [Pet]
    iq: Int
  }

  type Alien implements Being & Intelligent {
    name: String
    iq: Int
  }

  union DogOrHuman = Dog | Human

  union HumanOrAlien = Human | Alien

  type Query {
    catOrDog: CatOrDog
    dogOrHuman: DogOrHuman
    humanOrAlien: HumanOrAlien
  }
''');

  group('Validate: Possible fragment spreads', () {
    test('of the same object', () {
      expect(
        port.errors('''
      fragment objectWithinObject on Dog { ...dogFragment }
      fragment dogFragment on Dog { barkVolume }
    '''),
        isEmpty,
      );
    });

    test('of the same object with inline fragment', () {
      expect(
        port.errors('''
      fragment objectWithinObjectAnon on Dog { ... on Dog { barkVolume } }
    '''),
        isEmpty,
      );
    });

    test('object into an implemented interface', () {
      expect(
        port.errors('''
      fragment objectWithinInterface on Pet { ...dogFragment }
      fragment dogFragment on Dog { barkVolume }
    '''),
        isEmpty,
      );
    });

    test('object into containing union', () {
      expect(
        port.errors('''
      fragment objectWithinUnion on CatOrDog { ...dogFragment }
      fragment dogFragment on Dog { barkVolume }
    '''),
        isEmpty,
      );
    });

    test('union into contained object', () {
      expect(
        port.errors('''
      fragment unionWithinObject on Dog { ...catOrDogFragment }
      fragment catOrDogFragment on CatOrDog { __typename }
    '''),
        isEmpty,
      );
    });

    test('union into overlapping interface', () {
      expect(
        port.errors('''
      fragment unionWithinInterface on Pet { ...catOrDogFragment }
      fragment catOrDogFragment on CatOrDog { __typename }
    '''),
        isEmpty,
      );
    });

    test('union into overlapping union', () {
      expect(
        port.errors('''
      fragment unionWithinUnion on DogOrHuman { ...catOrDogFragment }
      fragment catOrDogFragment on CatOrDog { __typename }
    '''),
        isEmpty,
      );
    });

    test('interface into implemented object', () {
      expect(
        port.errors('''
      fragment interfaceWithinObject on Dog { ...petFragment }
      fragment petFragment on Pet { name }
    '''),
        isEmpty,
      );
    });

    test('interface into overlapping interface', () {
      expect(
        port.errors('''
      fragment interfaceWithinInterface on Pet { ...beingFragment }
      fragment beingFragment on Being { name }
    '''),
        isEmpty,
      );
    });

    test('interface into overlapping interface in inline fragment', () {
      expect(
        port.errors('''
      fragment interfaceWithinInterface on Pet { ... on Being { name } }
    '''),
        isEmpty,
      );
    });

    test('interface into overlapping union', () {
      expect(
        port.errors('''
      fragment interfaceWithinUnion on CatOrDog { ...petFragment }
      fragment petFragment on Pet { name }
    '''),
        isEmpty,
      );
    });

    test(
      'ignores incorrect type (caught by FragmentsOnCompositeTypesRule)',
      () {
        expect(
          port.errors('''
      fragment petFragment on Pet { ...badInADifferentWay }
      fragment badInADifferentWay on String { name }
    '''),
          isEmpty,
        );
      },
    );

    test('ignores unknown fragments (caught by KnownFragmentNamesRule)', () {
      expect(
        port.errors('''
      fragment petFragment on Pet { ...UnknownFragment }
    '''),
        isEmpty,
      );
    });

    test('different object into object', () {
      expect(
        port.errors('''
      fragment invalidObjectWithinObject on Cat { ...dogFragment }
      fragment dogFragment on Dog { barkVolume }
    '''),
        [
          'Fragment "dogFragment" cannot be spread here as objects of type "Cat" can never be of type "Dog". @ 2:51',
        ],
      );
    });

    test('different object into object in inline fragment', () {
      expect(
        port.errors('''
      fragment invalidObjectWithinObjectAnon on Cat {
        ... on Dog { barkVolume }
      }
    '''),
        [
          'Fragment cannot be spread here as objects of type "Cat" can never be of type "Dog". @ 3:9',
        ],
      );
    });

    test('object into not implementing interface', () {
      expect(
        port.errors('''
      fragment invalidObjectWithinInterface on Pet { ...humanFragment }
      fragment humanFragment on Human { pets { name } }
    '''),
        [
          'Fragment "humanFragment" cannot be spread here as objects of type "Pet" can never be of type "Human". @ 2:54',
        ],
      );
    });

    test('object into not containing union', () {
      expect(
        port.errors('''
      fragment invalidObjectWithinUnion on CatOrDog { ...humanFragment }
      fragment humanFragment on Human { pets { name } }
    '''),
        [
          'Fragment "humanFragment" cannot be spread here as objects of type "CatOrDog" can never be of type "Human". @ 2:55',
        ],
      );
    });

    test('union into not contained object', () {
      expect(
        port.errors('''
      fragment invalidUnionWithinObject on Human { ...catOrDogFragment }
      fragment catOrDogFragment on CatOrDog { __typename }
    '''),
        [
          'Fragment "catOrDogFragment" cannot be spread here as objects of type "Human" can never be of type "CatOrDog". @ 2:52',
        ],
      );
    });

    test('union into non overlapping interface', () {
      expect(
        port.errors('''
      fragment invalidUnionWithinInterface on Pet { ...humanOrAlienFragment }
      fragment humanOrAlienFragment on HumanOrAlien { __typename }
    '''),
        [
          'Fragment "humanOrAlienFragment" cannot be spread here as objects of type "Pet" can never be of type "HumanOrAlien". @ 2:53',
        ],
      );
    });

    test('union into non overlapping union', () {
      expect(
        port.errors('''
      fragment invalidUnionWithinUnion on CatOrDog { ...humanOrAlienFragment }
      fragment humanOrAlienFragment on HumanOrAlien { __typename }
    '''),
        [
          'Fragment "humanOrAlienFragment" cannot be spread here as objects of type "CatOrDog" can never be of type "HumanOrAlien". @ 2:54',
        ],
      );
    });

    test('interface into non implementing object', () {
      expect(
        port.errors('''
      fragment invalidInterfaceWithinObject on Cat { ...intelligentFragment }
      fragment intelligentFragment on Intelligent { iq }
    '''),
        [
          'Fragment "intelligentFragment" cannot be spread here as objects of type "Cat" can never be of type "Intelligent". @ 2:54',
        ],
      );
    });

    test('interface into non overlapping interface', () {
      expect(
        port.errors('''
      fragment invalidInterfaceWithinInterface on Pet {
        ...intelligentFragment
      }
      fragment intelligentFragment on Intelligent { iq }
    '''),
        [
          'Fragment "intelligentFragment" cannot be spread here as objects of type "Pet" can never be of type "Intelligent". @ 3:9',
        ],
      );
    });

    test('interface into non overlapping interface in inline fragment', () {
      expect(
        port.errors('''
      fragment invalidInterfaceWithinInterfaceAnon on Pet {
        ...on Intelligent { iq }
      }
    '''),
        [
          'Fragment cannot be spread here as objects of type "Pet" can never be of type "Intelligent". @ 3:9',
        ],
      );
    });

    test('interface into non overlapping union', () {
      expect(
        port.errors('''
      fragment invalidInterfaceWithinUnion on HumanOrAlien { ...petFragment }
      fragment petFragment on Pet { name }
    '''),
        [
          'Fragment "petFragment" cannot be spread here as objects of type "HumanOrAlien" can never be of type "Pet". @ 2:62',
        ],
      );
    });
  });
}
