import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownDirectivesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  // graphql-js's one rule is two here (M4 spec section 5).
  final port = RulePort.all(
    const [KnownDirectivesRule(), DirectivesInValidLocationsRule()],
    schema: RulePort.validated(_schemaWithDirectives),
  );

  group('Validate: Known directives', () {
    test('with no directives', () {
      expect(
        port.errors('''
      query Foo {
        name
        ...Frag
      }

      fragment Frag on Dog {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('with standard directives', () {
      expect(
        port.errors('''
      {
        human @skip(if: false) {
          name
          pets {
            ... on Dog @include(if: true) {
              name
            }
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('with unknown directive', () {
      expect(
        port.errors('''
      {
        human @unknown(directive: "value") {
          name
        }
      }
    '''),
        [
          'Unknown directive "@unknown". @ 3:15',
        ],
      );
    });

    test('with many unknown directives', () {
      expect(
        port.errors('''
      {
        __typename @unknown
        human @unknown {
          name
          pets @unknown {
            name
          }
        }
      }
    '''),
        [
          'Unknown directive "@unknown". @ 3:20',
          'Unknown directive "@unknown". @ 4:15',
          'Unknown directive "@unknown". @ 6:16',
        ],
      );
    });

    test('with well placed directives', () {
      expect(
        port.errors(r'''
      query ($var: Boolean @onVariableDefinition) @onQuery {
        human @onField {
          ...Frag @onFragmentSpread
          ... @onInlineFragment {
            name @onField
          }
        }
      }

      mutation @onMutation {
        someField @onField
      }

      subscription @onSubscription {
        someField @onField
      }

      fragment Frag on Human @onFragmentDefinition {
        name @onField
      }
    '''),
        isEmpty,
      );
    });

    test('with misplaced directives', () {
      expect(
        port.errors(r'''
      query ($var: Boolean @onQuery) @onMutation {
        human @onQuery {
          ...Frag @onQuery
          ... @onQuery {
            name @onQuery
          }
        }
      }

      mutation @onQuery {
        someField @onQuery
      }

      subscription @onQuery {
        someField @onQuery
      }

      fragment Frag on Human @onQuery {
        name @onQuery
      }
    '''),
        [
          'Directive "@onQuery" may not be used on VARIABLE_DEFINITION. @ 2:28',
          'Directive "@onMutation" may not be used on QUERY. @ 2:38',
          'Directive "@onQuery" may not be used on FIELD. @ 3:15',
          'Directive "@onQuery" may not be used on FRAGMENT_SPREAD. @ 4:19',
          'Directive "@onQuery" may not be used on INLINE_FRAGMENT. @ 5:15',
          'Directive "@onQuery" may not be used on FIELD. @ 6:18',
          'Directive "@onQuery" may not be used on MUTATION. @ 11:16',
          'Directive "@onQuery" may not be used on FIELD. @ 12:19',
          'Directive "@onQuery" may not be used on SUBSCRIPTION. @ 15:20',
          'Directive "@onQuery" may not be used on FIELD. @ 16:19',
          'Directive "@onQuery" may not be used on FRAGMENT_DEFINITION. @ 19:30',
          'Directive "@onQuery" may not be used on FIELD. @ 20:14',
        ],
      );
    });
  });
}

const _schemaWithDirectives = '''
  type Query {
    dummy: String
  }

  directive @onQuery on QUERY
  directive @onMutation on MUTATION
  directive @onSubscription on SUBSCRIPTION
  directive @onField on FIELD
  directive @onFragmentDefinition on FRAGMENT_DEFINITION
  directive @onFragmentSpread on FRAGMENT_SPREAD
  directive @onInlineFragment on INLINE_FRAGMENT
  directive @onVariableDefinition on VARIABLE_DEFINITION
''';
