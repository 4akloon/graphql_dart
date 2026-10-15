import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/FieldsOnCorrectTypeRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const FieldsOnCorrectTypeRule()).withSchema('''
  interface Pet {
    name: String
  }

  type Dog implements Pet {
    name: String
    nickname: String
    barkVolume: Int
  }

  type Cat implements Pet {
    name: String
    nickname: String
    meowVolume: Int
  }

  union CatOrDog = Cat | Dog

  type Human {
    name: String
    pets: [Pet]
  }

  type Query {
    human: Human
  }
''');

  group('Validate: Fields on correct type', () {
    test('Object field selection', () {
      expect(
        port.errors('''
      fragment objectFieldSelection on Dog {
        __typename
        name
      }
    '''),
        isEmpty,
      );
    });

    test('Aliased object field selection', () {
      expect(
        port.errors('''
      fragment aliasedObjectFieldSelection on Dog {
        tn : __typename
        otherName : name
      }
    '''),
        isEmpty,
      );
    });

    test('Interface field selection', () {
      expect(
        port.errors('''
      fragment interfaceFieldSelection on Pet {
        __typename
        name
      }
    '''),
        isEmpty,
      );
    });

    test('Aliased interface field selection', () {
      expect(
        port.errors('''
      fragment interfaceFieldSelection on Pet {
        otherName : name
      }
    '''),
        isEmpty,
      );
    });

    test('Lying alias selection', () {
      expect(
        port.errors('''
      fragment lyingAliasSelection on Dog {
        name : nickname
      }
    '''),
        isEmpty,
      );
    });

    test('Ignores fields on unknown type', () {
      expect(
        port.errors('''
      fragment unknownSelection on UnknownType {
        unknownField
      }
    '''),
        isEmpty,
      );
    });

    test('reports errors when type is known again', () {
      expect(
        port.errors('''
      fragment typeKnownAgain on Pet {
        unknown_pet_field {
          ... on Cat {
            unknown_cat_field
          }
        }
      }
    '''),
        [
          'Cannot query field "unknown_pet_field" on type "Pet". @ 3:9',
          'Cannot query field "unknown_cat_field" on type "Cat". @ 5:13',
        ],
      );
    });

    test('Field not defined on fragment', () {
      expect(
        port.errors('''
      fragment fieldNotDefined on Dog {
        meowVolume
      }
    '''),
        [
          'Cannot query field "meowVolume" on type "Dog". Did you mean "barkVolume"? @ 3:9',
        ],
      );
    });

    test('Field not defined on fragment (no suggestions)', () {
      expect(
        port.errors('''
      fragment fieldNotDefined on Dog {
        meowVolume
      }
    ''', hidesSuggestions: true),
        [
          'Cannot query field "meowVolume" on type "Dog". @ 3:9',
        ],
      );
    });

    test('Ignores deeply unknown field', () {
      expect(
        port.errors('''
      fragment deepFieldNotDefined on Dog {
        unknown_field {
          deeper_unknown_field
        }
      }
    '''),
        [
          'Cannot query field "unknown_field" on type "Dog". @ 3:9',
        ],
      );
    });

    test('Sub-field not defined', () {
      expect(
        port.errors('''
      fragment subFieldNotDefined on Human {
        pets {
          unknown_field
        }
      }
    '''),
        [
          'Cannot query field "unknown_field" on type "Pet". @ 4:11',
        ],
      );
    });

    test('Field not defined on inline fragment', () {
      expect(
        port.errors('''
      fragment fieldNotDefined on Pet {
        ... on Dog {
          meowVolume
        }
      }
    '''),
        [
          'Cannot query field "meowVolume" on type "Dog". Did you mean "barkVolume"? @ 4:11',
        ],
      );
    });

    test('Aliased field target not defined', () {
      expect(
        port.errors('''
      fragment aliasedFieldTargetNotDefined on Dog {
        volume : mooVolume
      }
    '''),
        [
          'Cannot query field "mooVolume" on type "Dog". Did you mean "barkVolume"? @ 3:9',
        ],
      );
    });

    test('Aliased lying field target not defined', () {
      expect(
        port.errors('''
      fragment aliasedLyingFieldTargetNotDefined on Dog {
        barkVolume : kawVolume
      }
    '''),
        [
          'Cannot query field "kawVolume" on type "Dog". Did you mean "barkVolume"? @ 3:9',
        ],
      );
    });

    test('Not defined on interface', () {
      expect(
        port.errors('''
      fragment notDefinedOnInterface on Pet {
        tailLength
      }
    '''),
        [
          'Cannot query field "tailLength" on type "Pet". @ 3:9',
        ],
      );
    });

    test('Defined on implementors but not on interface', () {
      expect(
        port.errors('''
      fragment definedOnImplementorsButNotInterface on Pet {
        nickname
      }
    '''),
        [
          'Cannot query field "nickname" on type "Pet". Did you mean to use an inline fragment on "Cat" or "Dog"? @ 3:9',
        ],
      );
    });

    test('Meta field selection on union', () {
      expect(
        port.errors('''
      fragment directFieldSelectionOnUnion on CatOrDog {
        __typename
      }
    '''),
        isEmpty,
      );
    });

    test('Direct field selection on union', () {
      expect(
        port.errors('''
      fragment directFieldSelectionOnUnion on CatOrDog {
        directField
      }
    '''),
        [
          'Cannot query field "directField" on type "CatOrDog". @ 3:9',
        ],
      );
    });

    test('Defined on implementors queried on union', () {
      expect(
        port.errors('''
      fragment definedOnImplementorsQueriedOnUnion on CatOrDog {
        name
      }
    '''),
        [
          'Cannot query field "name" on type "CatOrDog". Did you mean to use an inline fragment on "Pet", "Cat", or "Dog"? @ 3:9',
        ],
      );
    });

    test('valid field in inline fragment', () {
      expect(
        port.errors('''
      fragment objectFieldSelection on Pet {
        ... on Dog {
          name
        }
        ... {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    group('Fields on correct type error message', () {
      String message(String sdl, String query) {
        final errors = RulePort(
          const FieldsOnCorrectTypeRule(),
        ).withSchema(sdl).errors(query);
        expect(errors, hasLength(1));
        return errors.single.split(' @ ').first;
      }

      test('Works with no suggestions', () {
        expect(
          message('''
        type T {
          fieldWithVeryLongNameThatWillNeverBeSuggested: String
        }
        type Query { t: T }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T".',
        );
      });

      test('Works with no small numbers of type suggestions', () {
        expect(
          message('''
        union T = A | B
        type Query { t: T }

        type A { f: String }
        type B { f: String }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean to use an inline fragment on "A" or "B"?',
        );
      });

      test('Works with no small numbers of field suggestions', () {
        expect(
          message('''
        type T {
          y: String
          z: String
        }
        type Query { t: T }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean "y" or "z"?',
        );
      });

      test('Only shows one set of suggestions at a time, preferring types', () {
        expect(
          message('''
        interface T {
          y: String
          z: String
        }
        type Query { t: T }

        type A implements T {
          f: String
          y: String
          z: String
        }
        type B implements T {
          f: String
          y: String
          z: String
        }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean to use an inline fragment on "A" or "B"?',
        );
      });

      test('Sort type suggestions based on inheritance order', () {
        expect(
          message('''
        interface T { bar: String }
        type Query { t: T }

        interface Z implements T {
          foo: String
          bar: String
        }

        interface Y implements Z & T {
          foo: String
          bar: String
        }

        type X implements Y & Z & T {
          foo: String
          bar: String
        }
      ''', '{ t { foo } }'),
          'Cannot query field "foo" on type "T". Did you mean to use an inline fragment on "Z", "Y", or "X"?',
        );

        expect(
          message('''
        interface Animal { name: String }
        interface Mammal implements Animal { name: String }

        interface Canine implements Animal & Mammal { name: String }
        type Dog implements Animal & Mammal & Canine { name: String }

        interface Feline implements Animal & Mammal { name: String }
        type Cat implements Animal & Mammal & Feline { name: String }

        union CatOrDog = Cat | Dog
        type Query { catOrDog: CatOrDog }
      ''', '{ catOrDog { name } }'),
          'Cannot query field "name" on type "CatOrDog". Did you mean to use an inline fragment on "Animal", "Mammal", "Canine", "Dog", or "Feline"?',
        );
      });

      test('Limits lots of type suggestions', () {
        expect(
          message('''
        union T = A | B | C | D | E | F
        type Query { t: T }

        type A { f: String }
        type B { f: String }
        type C { f: String }
        type D { f: String }
        type E { f: String }
        type F { f: String }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean to use an inline fragment on "A", "B", "C", "D", or "E"?',
        );
      });

      test('Limits lots of field suggestions', () {
        expect(
          message('''
        type T {
          u: String
          v: String
          w: String
          x: String
          y: String
          z: String
        }
        type Query { t: T }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean "u", "v", "w", "x", or "y"?',
        );
      });
    });
  });
}
