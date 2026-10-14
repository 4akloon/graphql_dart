import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueFragmentNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueFragmentNamesRule());

  group('Validate: Unique fragment names', () {
    test('no fragments', () {
      expect(
        port.errors('''
      {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('one fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
      }

      fragment fragA on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('many fragments', () {
      expect(
        port.errors('''
      {
        ...fragA
        ...fragB
        ...fragC
      }
      fragment fragA on Type {
        fieldA
      }
      fragment fragB on Type {
        fieldB
      }
      fragment fragC on Type {
        fieldC
      }
    '''),
        isEmpty,
      );
    });

    test('inline fragments are always unique', () {
      expect(
        port.errors('''
      {
        ...on Type {
          fieldA
        }
        ...on Type {
          fieldB
        }
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

    test('fragments named the same', () {
      expect(
        port.errors('''
      {
        ...fragA
      }
      fragment fragA on Type {
        fieldA
      }
      fragment fragA on Type {
        fieldB
      }
    '''),
        [
          'There can be only one fragment named "fragA". @ 5:16 8:16',
        ],
      );
    });

    test('fragments named the same without being referenced', () {
      expect(
        port.errors('''
      fragment fragA on Type {
        fieldA
      }
      fragment fragA on Type {
        fieldB
      }
    '''),
        [
          'There can be only one fragment named "fragA". @ 2:16 5:16',
        ],
      );
    });
  });
}
