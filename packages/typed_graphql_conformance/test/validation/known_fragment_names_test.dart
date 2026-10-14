import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownFragmentNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const KnownFragmentNamesRule());

  group('Validate: Known fragment names', () {
    test('known fragment names are valid', () {
      expect(
        port.errors('''
      {
        human(id: 4) {
          ...HumanFields1
          ... on Human {
            ...HumanFields2
          }
          ... {
            name
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

    test('unknown fragment names are invalid', () {
      expect(
        port.errors('''
      {
        human(id: 4) {
          ...UnknownFragment1
          ... on Human {
            ...UnknownFragment2
          }
        }
      }
      fragment HumanFields on Human {
        name
        ...UnknownFragment3
      }
    '''),
        [
          'Unknown fragment "UnknownFragment1". @ 4:14',
          'Unknown fragment "UnknownFragment2". @ 6:16',
          'Unknown fragment "UnknownFragment3". @ 12:12',
        ],
      );
    });
  });
}
