import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoFragmentCyclesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoFragmentCyclesRule());

  group('Validate: No circular fragment spreads', () {
    test('single reference is valid', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB }
      fragment fragB on Dog { name }
    '''),
        isEmpty,
      );
    });

    test('spreading twice is not circular', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB, ...fragB }
      fragment fragB on Dog { name }
    '''),
        isEmpty,
      );
    });

    test('spreading twice indirectly is not circular', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB, ...fragC }
      fragment fragB on Dog { ...fragC }
      fragment fragC on Dog { name }
    '''),
        isEmpty,
      );
    });

    test('double spread within abstract types', () {
      expect(
        port.errors('''
      fragment nameFragment on Pet {
        ... on Dog { name }
        ... on Cat { name }
      }

      fragment spreadsInAnon on Pet {
        ... on Dog { ...nameFragment }
        ... on Cat { ...nameFragment }
      }
    '''),
        isEmpty,
      );
    });

    test('does not false positive on unknown fragment', () {
      expect(
        port.errors('''
      fragment nameFragment on Pet {
        ...UnknownFragment
      }
    '''),
        isEmpty,
      );
    });

    test('spreading recursively within field fails', () {
      expect(
        port.errors('''
      fragment fragA on Human { relatives { ...fragA } },
    '''),
        [
          'Cannot spread fragment "fragA" within itself. @ 2:45',
        ],
      );
    });

    test('no spreading itself directly', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragA }
    '''),
        [
          'Cannot spread fragment "fragA" within itself. @ 2:31',
        ],
      );
    });

    test('no spreading itself directly within inline fragment', () {
      expect(
        port.errors('''
      fragment fragA on Pet {
        ... on Dog {
          ...fragA
        }
      }
    '''),
        [
          'Cannot spread fragment "fragA" within itself. @ 4:11',
        ],
      );
    });

    test('no spreading itself indirectly', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB }
      fragment fragB on Dog { ...fragA }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragB". @ 2:31 3:31',
        ],
      );
    });

    test('no spreading itself indirectly reports opposite order', () {
      expect(
        port.errors('''
      fragment fragB on Dog { ...fragA }
      fragment fragA on Dog { ...fragB }
    '''),
        [
          'Cannot spread fragment "fragB" within itself via "fragA". @ 2:31 3:31',
        ],
      );
    });

    test('no spreading itself indirectly within inline fragment', () {
      expect(
        port.errors('''
      fragment fragA on Pet {
        ... on Dog {
          ...fragB
        }
      }
      fragment fragB on Pet {
        ... on Dog {
          ...fragA
        }
      }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragB". @ 4:11 9:11',
        ],
      );
    });

    test('no spreading itself deeply', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB }
      fragment fragB on Dog { ...fragC }
      fragment fragC on Dog { ...fragO }
      fragment fragX on Dog { ...fragY }
      fragment fragY on Dog { ...fragZ }
      fragment fragZ on Dog { ...fragO }
      fragment fragO on Dog { ...fragP }
      fragment fragP on Dog { ...fragA, ...fragX }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragB", "fragC", "fragO", "fragP". @ 2:31 3:31 4:31 8:31 9:31',
          'Cannot spread fragment "fragO" within itself via "fragP", "fragX", "fragY", "fragZ". @ 8:31 9:41 5:31 6:31 7:31',
        ],
      );
    });

    test('no spreading itself deeply two paths', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB, ...fragC }
      fragment fragB on Dog { ...fragA }
      fragment fragC on Dog { ...fragA }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragB". @ 2:31 3:31',
          'Cannot spread fragment "fragA" within itself via "fragC". @ 2:41 4:31',
        ],
      );
    });

    test('no spreading itself deeply two paths -- alt traverse order', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragC }
      fragment fragB on Dog { ...fragC }
      fragment fragC on Dog { ...fragA, ...fragB }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragC". @ 2:31 4:31',
          'Cannot spread fragment "fragC" within itself via "fragB". @ 4:41 3:31',
        ],
      );
    });

    test('no spreading itself deeply and immediately', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB }
      fragment fragB on Dog { ...fragB, ...fragC }
      fragment fragC on Dog { ...fragA, ...fragB }
    '''),
        [
          'Cannot spread fragment "fragB" within itself. @ 3:31',
          'Cannot spread fragment "fragA" within itself via "fragB", "fragC". @ 2:31 3:41 4:31',
          'Cannot spread fragment "fragB" within itself via "fragC". @ 3:41 4:41',
        ],
      );
    });
  });
}
