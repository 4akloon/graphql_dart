import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueVariableNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueVariableNamesRule());

  group('Validate: Unique variable names', () {
    test('unique variable names', () {
      expect(
        port.errors(r'''
      query A($x: Int, $y: String) { __typename }
      query B($x: String, $y: Int) { __typename }
    '''),
        isEmpty,
      );
    });

    test('duplicate variable names', () {
      expect(
        port.errors(r'''
      query A($x: Int, $x: Int, $x: String) { __typename }
      query B($x: String, $x: Int) { __typename }
      query C($x: Int, $x: Int) { __typename }
    '''),
        [
          r'There can be only one variable named "$x". @ 2:16 2:25 2:34',
          r'There can be only one variable named "$x". @ 3:16 3:28',
          r'There can be only one variable named "$x". @ 4:16 4:25',
        ],
      );
    });
  });
}
