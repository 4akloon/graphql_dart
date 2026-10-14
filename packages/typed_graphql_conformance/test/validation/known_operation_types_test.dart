import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownOperationTypesRules-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const KnownOperationTypesRule());

  group('Validate: Known operation types', () {
    test('one known operation', () {
      expect(
        port.errors('''
      { field }
    '''),
        isEmpty,
      );
    });

    test('unknown mutation operation', () {
      expect(
        port.errors('''
      mutation { field }
    '''),
        [
          'The mutation operation is not supported by the schema. @ 2:7',
        ],
      );
    });

    test('unknown subscription operation', () {
      expect(
        port.errors('''
      subscription { field }
    '''),
        [
          'The subscription operation is not supported by the schema. @ 2:7',
        ],
      );
    });

    test('mixture of known and unknown operations', () {
      expect(
        port.errors('''
      query { field }
      mutation { field }
      subscription { field }
  '''),
        [
          'The mutation operation is not supported by the schema. @ 3:7',
          'The subscription operation is not supported by the schema. @ 4:7',
        ],
      );
    });
  });
}
