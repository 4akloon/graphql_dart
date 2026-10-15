import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoUnusedFragmentsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoUnusedFragmentsRule());

  group('Validate: No unused fragments', () {
    test('all fragment names are used', () {
      expect(
        port.errors('''
      {
        human(id: 4) {
          ...HumanFields1
          ... on Human {
            ...HumanFields2
          }
        }
      }
      fragment HumanFields1 on Human {
        name
        ...HumanFields3
      }
      fragment HumanFields2 on Human {
        name
      }
      fragment HumanFields3 on Human {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('all fragment names are used by multiple operations', () {
      expect(
        port.errors('''
      query Foo {
        human(id: 4) {
          ...HumanFields1
        }
      }
      query Bar {
        human(id: 4) {
          ...HumanFields2
        }
      }
      fragment HumanFields1 on Human {
        name
        ...HumanFields3
      }
      fragment HumanFields2 on Human {
        name
      }
      fragment HumanFields3 on Human {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('contains unknown fragments', () {
      expect(
        port.errors('''
      query Foo {
        human(id: 4) {
          ...HumanFields1
        }
      }
      query Bar {
        human(id: 4) {
          ...HumanFields2
        }
      }
      fragment HumanFields1 on Human {
        name
        ...HumanFields3
      }
      fragment HumanFields2 on Human {
        name
      }
      fragment HumanFields3 on Human {
        name
      }
      fragment Unused1 on Human {
        name
      }
      fragment Unused2 on Human {
        name
      }
    '''),
        [
          'Fragment "Unused1" is never used. @ 22:7',
          'Fragment "Unused2" is never used. @ 25:7',
        ],
      );
    });

    test('contains unknown fragments with ref cycle', () {
      expect(
        port.errors('''
      query Foo {
        human(id: 4) {
          ...HumanFields1
        }
      }
      query Bar {
        human(id: 4) {
          ...HumanFields2
        }
      }
      fragment HumanFields1 on Human {
        name
        ...HumanFields3
      }
      fragment HumanFields2 on Human {
        name
      }
      fragment HumanFields3 on Human {
        name
      }
      fragment Unused1 on Human {
        name
        ...Unused2
      }
      fragment Unused2 on Human {
        name
        ...Unused1
      }
    '''),
        [
          'Fragment "Unused1" is never used. @ 22:7',
          'Fragment "Unused2" is never used. @ 26:7',
        ],
      );
    });

    test('contains unknown and undef fragments', () {
      expect(
        port.errors('''
      query Foo {
        human(id: 4) {
          ...bar
        }
      }
      fragment foo on Human {
        name
      }
    '''),
        [
          'Fragment "foo" is never used. @ 7:7',
        ],
      );
    });
  });
}
