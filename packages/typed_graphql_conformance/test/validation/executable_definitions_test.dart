import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ExecutableDefinitionsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const ExecutableDefinitionsRule());

  group('Validate: Executable definitions', () {
    test('with only operation', () {
      expect(
        port.errors('''
      query Foo {
        dog {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    test('with operation and fragment', () {
      expect(
        port.errors('''
      query Foo {
        dog {
          name
          ...Frag
        }
      }

      fragment Frag on Dog {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('with type definition', () {
      expect(
        port.errors('''
      query Foo {
        dog {
          name
        }
      }

      type Cow {
        name: String
      }

      extend type Dog {
        color: String
      }
    '''),
        [
          'The "Cow" definition is not executable. @ 8:7',
          'The "Dog" definition is not executable. @ 12:7',
        ],
      );
    });

    test('with schema definition', () {
      expect(
        port.errors('''
      schema {
        query: Query
      }

      type Query {
        test: String
      }

      extend schema @directive
    '''),
        [
          'The schema definition is not executable. @ 2:7',
          'The "Query" definition is not executable. @ 6:7',
          'The schema definition is not executable. @ 10:7',
        ],
      );
    });
  });
}
