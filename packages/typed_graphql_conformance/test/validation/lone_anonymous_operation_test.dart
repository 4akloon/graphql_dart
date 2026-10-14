import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/LoneAnonymousOperationRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const LoneAnonymousOperationRule());

  group('Validate: Anonymous operation must be alone', () {
    test('no operations', () {
      expect(
        port.errors('''
      fragment fragA on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('one anon operation', () {
      expect(
        port.errors('''
      {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('multiple named operations', () {
      expect(
        port.errors('''
      query Foo {
        field
      }

      query Bar {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('anon operation with fragment', () {
      expect(
        port.errors('''
      {
        ...Foo
      }
      fragment Foo on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('multiple anon operations', () {
      expect(
        port.errors('''
      {
        fieldA
      }
      {
        fieldB
      }
    '''),
        [
          'This anonymous operation must be the only defined operation. @ 2:7',
          'This anonymous operation must be the only defined operation. @ 5:7',
        ],
      );
    });

    test('anon operation with a mutation', () {
      expect(
        port.errors('''
      {
        fieldA
      }
      mutation Foo {
        fieldB
      }
    '''),
        [
          'This anonymous operation must be the only defined operation. @ 2:7',
        ],
      );
    });

    test('anon operation with a subscription', () {
      expect(
        port.errors('''
      {
        fieldA
      }
      subscription Foo {
        fieldB
      }
    '''),
        [
          'This anonymous operation must be the only defined operation. @ 2:7',
        ],
      );
    });
  });
}
