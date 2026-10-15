import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueOperationNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueOperationNamesRule());

  group('Validate: Unique operation names', () {
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

    test('one named operation', () {
      expect(
        port.errors('''
      query Foo {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('multiple operations', () {
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

    test('multiple operations of different types', () {
      expect(
        port.errors('''
      query Foo {
        field
      }

      mutation Bar {
        field
      }

      subscription Baz {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('fragment and operation named the same', () {
      expect(
        port.errors('''
      query Foo {
        ...Foo
      }
      fragment Foo on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('multiple operations of same name', () {
      expect(
        port.errors('''
      query Foo {
        fieldA
      }
      query Foo {
        fieldB
      }
    '''),
        [
          'There can be only one operation named "Foo". @ 2:13 5:13',
        ],
      );
    });

    test('multiple ops of same name of different types (mutation)', () {
      expect(
        port.errors('''
      query Foo {
        fieldA
      }
      mutation Foo {
        fieldB
      }
    '''),
        [
          'There can be only one operation named "Foo". @ 2:13 5:16',
        ],
      );
    });

    test('multiple ops of same name of different types (subscription)', () {
      expect(
        port.errors('''
      query Foo {
        fieldA
      }
      subscription Foo {
        fieldB
      }
    '''),
        [
          'There can be only one operation named "Foo". @ 2:13 5:20',
        ],
      );
    });
  });
}
