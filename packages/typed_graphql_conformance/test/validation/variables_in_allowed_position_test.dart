import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/VariablesInAllowedPositionRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const VariablesInAllowedPositionRule());

  group('Validate: Variables are in allowed positions', () {
    test('Boolean => Boolean', () {
      expect(
        port.errors(r'''
      query Query($booleanArg: Boolean)
      {
        complicatedArgs {
          booleanArgField(booleanArg: $booleanArg)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Boolean => Boolean within fragment', () {
      expect(
        port.errors(r'''
      fragment booleanArgFrag on ComplicatedArgs {
        booleanArgField(booleanArg: $booleanArg)
      }
      query Query($booleanArg: Boolean)
      {
        complicatedArgs {
          ...booleanArgFrag
        }
      }
    '''),
        isEmpty,
      );

      expect(
        port.errors(r'''
      query Query($booleanArg: Boolean)
      {
        complicatedArgs {
          ...booleanArgFrag
        }
      }
      fragment booleanArgFrag on ComplicatedArgs {
        booleanArgField(booleanArg: $booleanArg)
      }
    '''),
        isEmpty,
      );
    });

    test('Boolean! => Boolean', () {
      expect(
        port.errors(r'''
      query Query($nonNullBooleanArg: Boolean!)
      {
        complicatedArgs {
          booleanArgField(booleanArg: $nonNullBooleanArg)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Boolean! => Boolean within fragment', () {
      expect(
        port.errors(r'''
      fragment booleanArgFrag on ComplicatedArgs {
        booleanArgField(booleanArg: $nonNullBooleanArg)
      }

      query Query($nonNullBooleanArg: Boolean!)
      {
        complicatedArgs {
          ...booleanArgFrag
        }
      }
    '''),
        isEmpty,
      );
    });

    test('[String] => [String]', () {
      expect(
        port.errors(r'''
      query Query($stringListVar: [String])
      {
        complicatedArgs {
          stringListArgField(stringListArg: $stringListVar)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('[String!] => [String]', () {
      expect(
        port.errors(r'''
      query Query($stringListVar: [String!])
      {
        complicatedArgs {
          stringListArgField(stringListArg: $stringListVar)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('String => [String] in item position', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String)
      {
        complicatedArgs {
          stringListArgField(stringListArg: [$stringVar])
        }
      }
    '''),
        isEmpty,
      );
    });

    test('String! => [String] in item position', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String!)
      {
        complicatedArgs {
          stringListArgField(stringListArg: [$stringVar])
        }
      }
    '''),
        isEmpty,
      );
    });

    test('ComplexInput => ComplexInput', () {
      expect(
        port.errors(r'''
      query Query($complexVar: ComplexInput)
      {
        complicatedArgs {
          complexArgField(complexArg: $complexVar)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('ComplexInput => ComplexInput in field position', () {
      expect(
        port.errors(r'''
      query Query($boolVar: Boolean = false)
      {
        complicatedArgs {
          complexArgField(complexArg: {requiredArg: $boolVar})
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Boolean! => Boolean! in directive', () {
      expect(
        port.errors(r'''
      query Query($boolVar: Boolean!)
      {
        dog @include(if: $boolVar)
      }
    '''),
        isEmpty,
      );
    });

    test('Int => Int!', () {
      expect(
        port.errors(r'''
      query Query($intArg: Int) {
        complicatedArgs {
          nonNullIntArgField(nonNullIntArg: $intArg)
        }
      }
    '''),
        [
          r'Variable "$intArg" of type "Int" used in position expecting type "Int!". @ 2:19 4:45',
        ],
      );
    });

    test('Int => Int! within fragment', () {
      expect(
        port.errors(r'''
      fragment nonNullIntArgFieldFrag on ComplicatedArgs {
        nonNullIntArgField(nonNullIntArg: $intArg)
      }

      query Query($intArg: Int) {
        complicatedArgs {
          ...nonNullIntArgFieldFrag
        }
      }
    '''),
        [
          r'Variable "$intArg" of type "Int" used in position expecting type "Int!". @ 6:19 3:43',
        ],
      );
    });

    test('Int => Int! within nested fragment', () {
      expect(
        port.errors(r'''
      fragment outerFrag on ComplicatedArgs {
        ...nonNullIntArgFieldFrag
      }

      fragment nonNullIntArgFieldFrag on ComplicatedArgs {
        nonNullIntArgField(nonNullIntArg: $intArg)
      }

      query Query($intArg: Int) {
        complicatedArgs {
          ...outerFrag
        }
      }
    '''),
        [
          r'Variable "$intArg" of type "Int" used in position expecting type "Int!". @ 10:19 7:43',
        ],
      );
    });

    test('String over Boolean', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String) {
        complicatedArgs {
          booleanArgField(booleanArg: $stringVar)
        }
      }
    '''),
        [
          r'Variable "$stringVar" of type "String" used in position expecting type "Boolean". @ 2:19 4:39',
        ],
      );
    });

    test('String => [String]', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String) {
        complicatedArgs {
          stringListArgField(stringListArg: $stringVar)
        }
      }
    '''),
        [
          r'Variable "$stringVar" of type "String" used in position expecting type "[String]". @ 2:19 4:45',
        ],
      );
    });

    test('Boolean => Boolean! in directive', () {
      expect(
        port.errors(r'''
      query Query($boolVar: Boolean) {
        dog @include(if: $boolVar)
      }
    '''),
        [
          r'Variable "$boolVar" of type "Boolean" used in position expecting type "Boolean!". @ 2:19 3:26',
        ],
      );
    });

    test('String => Boolean! in directive', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String) {
        dog @include(if: $stringVar)
      }
    '''),
        [
          r'Variable "$stringVar" of type "String" used in position expecting type "Boolean!". @ 2:19 3:26',
        ],
      );
    });

    test('[String] => [String!]', () {
      expect(
        port.errors(r'''
      query Query($stringListVar: [String])
      {
        complicatedArgs {
          stringListNonNullArgField(stringListNonNullArg: $stringListVar)
        }
      }
    '''),
        [
          r'Variable "$stringListVar" of type "[String]" used in position expecting type "[String!]". @ 2:19 5:59',
        ],
      );
    });

    group('Allows optional (nullable) variables with default values', () {
      test('Int => Int! fails when variable provides null default value', () {
        expect(
          port.errors(r'''
        query Query($intVar: Int = null) {
          complicatedArgs {
            nonNullIntArgField(nonNullIntArg: $intVar)
          }
        }
      '''),
          [
            r'Variable "$intVar" of type "Int" used in position expecting type "Int!". @ 2:21 4:47',
          ],
        );
      });

      test('Int => Int! when variable provides non-null default value', () {
        expect(
          port.errors(r'''
        query Query($intVar: Int = 1) {
          complicatedArgs {
            nonNullIntArgField(nonNullIntArg: $intVar)
          }
        }'''),
          isEmpty,
        );
      });

      test('Int => Int! when optional argument provides default value', () {
        expect(
          port.errors(r'''
        query Query($intVar: Int) {
          complicatedArgs {
            nonNullFieldWithDefault(nonNullIntArg: $intVar)
          }
        }'''),
          isEmpty,
        );
      });

      test(
        'Boolean => Boolean! in directive with default value with option',
        () {
          expect(
            port.errors(r'''
        query Query($boolVar: Boolean = false) {
          dog @include(if: $boolVar)
        }'''),
            isEmpty,
          );
        },
      );

      test('undefined in directive with default value with option', () {
        expect(
          port.errors(r'''
        {
          dog @include(if: $x)
        }'''),
          isEmpty,
        );
      });
    });

    group('Validates OneOf Input Objects', () {
      test('Allows exactly one non-nullable variable', () {
        expect(
          port.errors(r'''
        query ($string: String!) {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: $string })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Forbids one nullable variable', () {
        expect(
          port.errors(r'''
        query ($string: String) {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: $string })
          }
        }
      '''),
          [
            r'Variable "$string" is of type "String" but must be non-nullable to be used for OneOf Input Object "OneOfInput". @ 2:16 4:52',
          ],
        );
      });
    });
  });

  group('Validates OneOf Input Objects', () {
    test('Allows exactly one non-nullable variable', () {
      expect(
        port.errors(r'''
      query ($string: String!) {
        complicatedArgs {
          oneOfArgField(oneOfArg: { stringField: $string })
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Undefined variable in oneOf input object', () {
      expect(
        port.errors(r'''
      {
        complicatedArgs {
          oneOfArgField(oneOfArg: { stringField: $undefinedVariable })
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Forbids one nullable variable', () {
      expect(
        port.errors(r'''
      query ($string: String) {
        complicatedArgs {
          oneOfArgField(oneOfArg: { stringField: $string })
        }
      }
    '''),
        [
          r'Variable "$string" is of type "String" but must be non-nullable to be used for OneOf Input Object "OneOfInput". @ 2:14 4:50',
        ],
      );
    });
  });

  group('Non-specified behavior of variables within custom scalars', () {
    test('Allows using variables inside object literal in custom scalar', () {
      expect(
        port.errors(r'''
      query Query($x: Float) {
        dog {
          distanceFrom(loc: {x: $x, y: 10.0})
        }
      }'''),
        isEmpty,
      );
    });

    test('Allows using variables inside list literal in custom scalar', () {
      expect(
        port.errors(r'''
      query Query($x: Float) {
        dog {
          distanceFrom(loc: [$x, 10.0])
        }
      }'''),
        isEmpty,
      );
    });
  });
}
