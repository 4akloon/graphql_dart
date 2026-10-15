import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoUndefinedVariablesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoUndefinedVariablesRule());

  group('Validate: No undefined variables', () {
    test('all variables defined', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        isEmpty,
      );
    });

    test('all variables deeply defined', () {
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

    test('all variables deeply in inline fragments defined', () {
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

    test('all variables in fragments deeply defined', () {
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

    test('variable within single fragment defined in multiple operations', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragA
      }
      query Bar($a: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a)
      }
    '''),
        isEmpty,
      );
    });

    test('variable within fragments defined in operations', () {
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

    test('variable within recursive fragment defined', () {
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

    test('variable not defined', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        field(a: $a, b: $b, c: $c, d: $d)
      }
    '''),
        [
          r'Variable "$d" is not defined by operation "Foo". @ 3:39 2:7',
        ],
      );
    });

    test('variable not defined by un-named query', () {
      expect(
        port.errors(r'''
      {
        field(a: $a)
      }
    '''),
        [
          r'Variable "$a" is not defined. @ 3:18 2:7',
        ],
      );
    });

    test('multiple variables not defined', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        [
          r'Variable "$a" is not defined by operation "Foo". @ 3:18 2:7',
          r'Variable "$c" is not defined by operation "Foo". @ 3:32 2:7',
        ],
      );
    });

    test('variable in fragment not defined by un-named query', () {
      expect(
        port.errors(r'''
      {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a)
      }
    '''),
        [
          r'Variable "$a" is not defined. @ 6:18 2:7',
        ],
      );
    });

    test('variable in fragment not defined by operation', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String) {
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
        [
          r'Variable "$c" is not defined by operation "Foo". @ 16:18 2:7',
        ],
      );
    });

    test('multiple variables in fragments not defined', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
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
        [
          r'Variable "$a" is not defined by operation "Foo". @ 6:18 2:7',
          r'Variable "$c" is not defined by operation "Foo". @ 16:18 2:7',
        ],
      );
    });

    test('single variable in fragment not defined by multiple operations', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragAB
      }
      query Bar($a: String) {
        ...FragAB
      }
      fragment FragAB on Type {
        field(a: $a, b: $b)
      }
    '''),
        [
          r'Variable "$b" is not defined by operation "Foo". @ 9:25 2:7',
          r'Variable "$b" is not defined by operation "Bar". @ 9:25 5:7',
        ],
      );
    });

    test('variables in fragment not defined by multiple operations', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragAB
      }
      query Bar($a: String) {
        ...FragAB
      }
      fragment FragAB on Type {
        field(a: $a, b: $b)
      }
    '''),
        [
          r'Variable "$a" is not defined by operation "Foo". @ 9:18 2:7',
          r'Variable "$b" is not defined by operation "Bar". @ 9:25 5:7',
        ],
      );
    });

    test('variable in fragment used by other operation', () {
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
          r'Variable "$a" is not defined by operation "Foo". @ 9:18 2:7',
          r'Variable "$b" is not defined by operation "Bar". @ 12:18 5:7',
        ],
      );
    });

    test('multiple undefined variables produce multiple errors', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragAB
      }
      query Bar($a: String) {
        ...FragAB
      }
      fragment FragAB on Type {
        field1(a: $a, b: $b)
        ...FragC
        field3(a: $a, b: $b)
      }
      fragment FragC on Type {
        field2(c: $c)
      }
    '''),
        [
          r'Variable "$a" is not defined by operation "Foo". @ 9:19 2:7',
          r'Variable "$a" is not defined by operation "Foo". @ 11:19 2:7',
          r'Variable "$c" is not defined by operation "Foo". @ 14:19 2:7',
          r'Variable "$b" is not defined by operation "Bar". @ 9:26 5:7',
          r'Variable "$b" is not defined by operation "Bar". @ 11:26 5:7',
          r'Variable "$c" is not defined by operation "Bar". @ 14:19 5:7',
        ],
      );
    });
  });
}
