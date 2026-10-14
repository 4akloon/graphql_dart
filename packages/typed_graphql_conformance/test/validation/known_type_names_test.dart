import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownTypeNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const KnownTypeNamesRule());

  group('Validate: Known type names', () {
    test('known type names are valid', () {
      expect(
        port.errors(r'''
      query Foo(
        $var: String
        $required: [Int!]!
        $introspectionType: __EnumValue
      ) {
        user(id: 4) {
          pets { ... on Pet { name }, ...PetFields, ... { name } }
        }
      }

      fragment PetFields on Pet {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('unknown type names are invalid', () {
      expect(
        port.errors(r'''
      query Foo($var: [JumbledUpLetters!]!) {
        user(id: 4) {
          name
          pets { ... on Badger { name }, ...PetFields }
        }
      }
      fragment PetFields on Peat {
        name
      }
    '''),
        [
          'Unknown type "JumbledUpLetters". @ 2:24',
          'Unknown type "Badger". @ 5:25',
          'Unknown type "Peat". Did you mean "Pet" or "Cat"? @ 8:29',
        ],
      );
    });

    test('unknown type names are invalid (no suggestions)', () {
      expect(
        port.errors(r'''
      query Foo($var: [JumbledUpLetters!]!) {
        user(id: 4) {
          name
          pets { ... on Badger { name }, ...PetFields }
        }
      }
      fragment PetFields on Peat {
        name
      }
    ''', hidesSuggestions: true),
        [
          'Unknown type "JumbledUpLetters". @ 2:24',
          'Unknown type "Badger". @ 5:25',
          'Unknown type "Peat". @ 8:29',
        ],
      );
    });

    test('references to standard scalars that are missing in schema', () {
      // Adapted: graphql-js's type map holds only the types the schema
      // reaches, so `ID`, `Float` and `Int` are unknown there. A schema here
      // always has the five built-in scalars (spec §3.5).
      final queryOnly = port.withSchema('type Query { foo: String }');
      expect(
        queryOnly.errors(r'''
      query ($id: ID, $float: Float, $int: Int) {
        __typename
      }
    '''),
        isEmpty,
      );
    });

    group('within SDL', () {
      test('use standard types', () {
        expect(
          port.errors('''
        type Query {
          string: String
          int: Int
          float: Float
          boolean: Boolean
          id: ID
          introspectionType: __EnumValue
        }
      '''),
          isEmpty,
        );
      });

      test('reference types defined inside the same document', () {
        expect(
          port.errors('''
        union SomeUnion = SomeObject | AnotherObject

        type SomeObject implements SomeInterface {
          someScalar(arg: SomeInputObject): SomeScalar
        }

        type AnotherObject {
          foo(arg: SomeInputObject): String
        }

        type SomeInterface {
          someScalar(arg: SomeInputObject): SomeScalar
        }

        input SomeInputObject {
          someScalar: SomeScalar
        }

        scalar SomeScalar

        type RootQuery {
          someInterface: SomeInterface
          someUnion: SomeUnion
          someScalar: SomeScalar
          someObject: SomeObject
        }

        schema {
          query: RootQuery
        }
      '''),
          isEmpty,
        );
      });

      test('does not consider non-type definitions', () {
        expect(
          port.errors('''
        query Foo { __typename }
        fragment Foo on Query { __typename }
        directive @Foo on QUERY

        type Query {
          foo: Foo
        }
      ''', hidesSuggestions: true),
          ['Unknown type "Foo". @ 7:16'],
        );
      });
    });
  });
}
