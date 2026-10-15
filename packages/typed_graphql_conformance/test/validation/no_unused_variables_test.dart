import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoUnusedVariablesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoUnusedVariablesRule());

  group('Validate: No unused variables', () {
    test('uses all variables', () {
      expect(
        port.errors(r'''
      query ($a: String, $b: String, $c: String) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        isEmpty,
      );
    });

    test('uses all variables deeply', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        field(a: $a) {
          field(b: $b) {
            field(c: $c)
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('uses all variables deeply in inline fragments', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ... on Type {
          field(a: $a) {
            field(b: $b) {
              ... on Type {
                field(c: $c)
              }
            }
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('uses all variables in fragments', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragB
        }
      }
      fragment FragB on Type {
        field(b: $b) {
          ...FragC
        }
      }
      fragment FragC on Type {
        field(c: $c)
      }
    '''),
        isEmpty,
      );
    });

    test('variable used by fragment in multiple operations', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragA
      }
      query Bar($b: String) {
        ...FragB
      }
      fragment FragA on Type {
        field(a: $a)
      }
      fragment FragB on Type {
        field(b: $b)
      }
    '''),
        isEmpty,
      );
    });

    test('variable used by recursive fragment', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragA
        }
      }
    '''),
        isEmpty,
      );
    });

    test('variable not used', () {
      expect(
        port.errors(r'''
      query ($a: String, $b: String, $c: String) {
        field(a: $a, b: $b)
      }
    '''),
        [
          r'Variable "$c" is never used. @ 2:38',
        ],
      );
    });

    test('multiple variables not used', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        field(b: $b)
      }
    '''),
        [
          r'Variable "$a" is never used in operation "Foo". @ 2:17',
          r'Variable "$c" is never used in operation "Foo". @ 2:41',
        ],
      );
    });

    test('variable not used in fragments', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragB
        }
      }
      fragment FragB on Type {
        field(b: $b) {
          ...FragC
        }
      }
      fragment FragC on Type {
        field
      }
    '''),
        [
          r'Variable "$c" is never used in operation "Foo". @ 2:41',
        ],
      );
    });

    test('multiple variables not used in fragments', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ...FragA
      }
      fragment FragA on Type {
        field {
          ...FragB
        }
      }
      fragment FragB on Type {
        field(b: $b) {
          ...FragC
        }
      }
      fragment FragC on Type {
        field
      }
    '''),
        [
          r'Variable "$a" is never used in operation "Foo". @ 2:17',
          r'Variable "$c" is never used in operation "Foo". @ 2:41',
        ],
      );
    });

    test('variable not used by unreferenced fragment', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a)
      }
      fragment FragB on Type {
        field(b: $b)
      }
    '''),
        [
          r'Variable "$b" is never used in operation "Foo". @ 2:17',
        ],
      );
    });

    test('variable not used by fragment used by other operation', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragA
      }
      query Bar($a: String) {
        ...FragB
      }
      fragment FragA on Type {
        field(a: $a)
      }
      fragment FragB on Type {
        field(b: $b)
      }
    '''),
        [
          r'Variable "$b" is never used in operation "Foo". @ 2:17',
          r'Variable "$a" is never used in operation "Bar". @ 5:17',
        ],
      );
    });
  });
}
