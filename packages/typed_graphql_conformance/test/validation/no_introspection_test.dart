import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoSchemaIntrospectionCustomRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoIntrospectionRule()).withSchema('''
    type Query {
      someQuery: SomeType
    }

    type SomeType {
      someField: String
      introspectionField: __EnumValue
    }
  ''');

  group('Validate: Prohibit introspection queries', () {
    test('ignores valid fields including __typename', () {
      expect(
        port.errors('''
      {
        someQuery {
          __typename
          someField
        }
      }
    '''),
        isEmpty,
      );
    });

    test('ignores fields not in the schema', () {
      expect(
        port.errors('''
      {
        __introspect
      }
    '''),
        isEmpty,
      );
    });

    test(
      'reports error when a field with an introspection type is requested',
      () {
        expect(
          port.errors('''
      {
        __schema {
          queryType {
            name
          }
        }
      }
    '''),
          [
            'GraphQL introspection has been disabled, but the requested query contained the field "__schema". @ 3:9',
            'GraphQL introspection has been disabled, but the requested query contained the field "queryType". @ 4:11',
          ],
        );
      },
    );

    test('reports error when a field with an introspection type is requested and aliased', () {
      expect(
        port.errors('''
      {
        s: __schema {
          queryType {
            name
          }
        }
      }
      '''),
        [
          'GraphQL introspection has been disabled, but the requested query contained the field "__schema". @ 3:9',
          'GraphQL introspection has been disabled, but the requested query contained the field "queryType". @ 4:11',
        ],
      );
    });

    test('reports error when using a fragment with a field with an introspection type', () {
      expect(
        port.errors('''
      {
        ...QueryFragment
      }

      fragment QueryFragment on Query {
        __schema {
          queryType {
            name
          }
        }
      }
    '''),
        [
          'GraphQL introspection has been disabled, but the requested query contained the field "__schema". @ 7:9',
          'GraphQL introspection has been disabled, but the requested query contained the field "queryType". @ 8:11',
        ],
      );
    });

    test('reports error for non-standard introspection fields', () {
      expect(
        port.errors('''
      {
        someQuery {
          introspectionField
        }
      }
    '''),
        [
          'GraphQL introspection has been disabled, but the requested query contained the field "introspectionField". @ 4:11',
        ],
      );
    });
  });
}
