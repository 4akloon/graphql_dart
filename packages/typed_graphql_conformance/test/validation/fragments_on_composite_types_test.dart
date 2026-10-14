import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/FragmentsOnCompositeTypesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const FragmentsOnCompositeTypesRule());

  group('Validate: Fragments on composite types', () {
    test('object is valid fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on Dog {
        barks
      }
    '''),
        isEmpty,
      );
    });

    test('interface is valid fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on Pet {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('object is valid inline fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on Pet {
        ... on Dog {
          barks
        }
      }
    '''),
        isEmpty,
      );
    });

    test('interface is valid inline fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on Mammal {
        ... on Canine {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    test('inline fragment without type is valid', () {
      expect(
        port.errors('''
      fragment validFragment on Pet {
        ... {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    test('union is valid fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on CatOrDog {
        __typename
      }
    '''),
        isEmpty,
      );
    });

    test('scalar is invalid fragment type', () {
      expect(
        port.errors('''
      fragment scalarFragment on Boolean {
        bad
      }
    '''),
        [
          'Fragment "scalarFragment" cannot condition on non composite type "Boolean". @ 2:34',
        ],
      );
    });

    test('enum is invalid fragment type', () {
      expect(
        port.errors('''
      fragment scalarFragment on FurColor {
        bad
      }
    '''),
        [
          'Fragment "scalarFragment" cannot condition on non composite type "FurColor". @ 2:34',
        ],
      );
    });

    test('input object is invalid fragment type', () {
      expect(
        port.errors('''
      fragment inputFragment on ComplexInput {
        stringField
      }
    '''),
        [
          'Fragment "inputFragment" cannot condition on non composite type "ComplexInput". @ 2:33',
        ],
      );
    });

    test('scalar is invalid inline fragment type', () {
      expect(
        port.errors('''
      fragment invalidFragment on Pet {
        ... on String {
          barks
        }
      }
    '''),
        [
          'Fragment cannot condition on non composite type "String". @ 3:16',
        ],
      );
    });
  });
}
