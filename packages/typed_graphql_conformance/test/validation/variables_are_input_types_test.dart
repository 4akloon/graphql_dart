import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/VariablesAreInputTypesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const VariablesAreInputTypesRule());

  group('Validate: Variables are input types', () {
    // Adapted: September2025 has no fragment arguments, so the fragment of
    // the graphql-js test is left out (mapping/validation.csv).
    test('unknown types are ignored', () {
      expect(
        port.errors(r'''
      query Foo($a: Unknown, $b: [[Unknown!]]!) {
        field(a: $a, b: $b)
      }
    '''),
        isEmpty,
      );
    });

    test('input types are valid', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: [Boolean!]!, $c: ComplexInput) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        isEmpty,
      );
    });

    test('output types are invalid', () {
      expect(
        port.errors(r'''
      query Foo($a: Dog, $b: [[CatOrDog!]]!, $c: Pet) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        [
          r'Variable "$a" cannot be non-input type "Dog". @ 2:21',
          r'Variable "$b" cannot be non-input type "[[CatOrDog!]]!". @ 2:30',
          r'Variable "$c" cannot be non-input type "Pet". @ 2:50',
        ],
      );
    });
  });
}
