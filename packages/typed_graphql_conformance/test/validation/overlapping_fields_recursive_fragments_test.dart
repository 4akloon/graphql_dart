import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js
// src/validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts
// (the recursive fragment tests); mapping/validation.csv says which tests
// are adapted or skipped, and why.
void main() {
  final port = RulePort(const OverlappingFieldsCanBeMergedRule());

  group('Validate: Overlapping fields can be merged', () {
    test('does not infinite loop on recursive fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
      }

      fragment fragA on Human { name, relatives { name, ...fragA } }
    '''),
        isEmpty,
      );
    });

    test('does not infinite loop on immediately recursive fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
      }

      fragment fragA on Human { name, ...fragA }
    '''),
        isEmpty,
      );
    });

    test('does not infinite loop on recursive fragment with a field named after fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
        fragA
      }

      fragment fragA on Query { ...fragA }
    '''),
        isEmpty,
      );
    });

    test('finds invalid cases even with field named after fragment', () {
      expect(
        port.errors('''
      {
        fragA
        ...fragA
      }

      fragment fragA on Type {
        fragA: b
      }
    '''),
        [
          'Fields "fragA" conflict because "fragA" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 8:9',
        ],
      );
    });

    test('does not infinite loop on transitively recursive fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
        fragB
      }

      fragment fragA on Human { name, ...fragB }
      fragment fragB on Human { name, ...fragC }
      fragment fragC on Human { name, ...fragA }
    '''),
        isEmpty,
      );
    });

    test('finds invalid case even with immediately recursive fragment', () {
      expect(
        port.errors('''
      fragment sameAliasesWithDifferentFieldTargets on Dog {
        ...sameAliasesWithDifferentFieldTargets
        fido: name
        fido: nickname
      }
    '''),
        [
          'Fields "fido" conflict because "name" and "nickname" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 4:9 5:9',
        ],
      );
    });

    test(
      'does not infinite loop on recursive fragments separated by fields',
      () {
        expect(
          port.errors('''
      {
        ...fragA
        ...fragB
      }

      fragment fragA on T {
        x {
          ...fragA
          x {
            ...fragA
          }
        }
      }

      fragment fragB on T {
        x {
          ...fragB
          x {
            ...fragB
          }
        }
      }
    '''),
          isEmpty,
        );
      },
    );
  });
}
