import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ValuesOfCorrectTypeRule-test.ts
// (one rule there, three here: M4 splits it by kind of problem);
// mapping/validation.csv says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort.all([
    const ValuesOfCorrectTypeRule(),
    const InputObjectFieldNamesRule(),
    const InputObjectRequiredFieldsRule(),
  ]);

  group('Validate: Values of correct type', () {
    group('Directive arguments', () {
      test('with directives of valid types', () {
        expect(
          port.errors('''
        {
          dog @include(if: true) {
            name
          }
          human @skip(if: false) {
            name
          }
        }
      '''),
          isEmpty,
        );
      });

      test('with directive with incorrect types', () {
        expect(
          port.errors('''
        {
          dog @include(if: "yes") {
            name @skip(if: ENUM)
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: "yes" @ 3:28',
            'Boolean cannot represent a non boolean value: ENUM @ 4:28',
          ],
        );
      });
    });

    group('Variable default values', () {
      test('variables with valid default values', () {
        expect(
          port.errors(r'''
        query WithDefaultValues(
          $a: Int = 1,
          $b: String = "ok",
          $c: ComplexInput = { requiredField: true, intField: 3 }
          $d: Int! = 123
        ) {
          dog { name }
        }
      '''),
          isEmpty,
        );
      });

      test('variables with valid default null values', () {
        expect(
          port.errors(r'''
        query WithDefaultValues(
          $a: Int = null,
          $b: String = null,
          $c: ComplexInput = { requiredField: true, intField: null }
        ) {
          dog { name }
        }
      '''),
          isEmpty,
        );
      });

      test('variables with invalid default null values', () {
        expect(
          port.errors(r'''
        query WithDefaultValues(
          $a: Int! = null,
          $b: String! = null,
          $c: ComplexInput = { requiredField: null, intField: null }
        ) {
          dog { name }
        }
      '''),
          [
            'Expected value of non-null type "Int!" not to be null. @ 3:22',
            'Expected value of non-null type "String!" not to be null. @ 4:25',
            'Expected value of non-null type "Boolean!" not to be null. @ 5:47',
          ],
        );
      });

      test('variables with invalid default values', () {
        expect(
          port.errors(r'''
        query InvalidDefaultValues(
          $a: Int = "one",
          $b: String = 4,
          $c: ComplexInput = "NotVeryComplex"
        ) {
          dog { name }
        }
      '''),
          [
            'Int cannot represent non-integer value: "one" @ 3:21',
            'String cannot represent a non string value: 4 @ 4:24',
            'Expected value of type "ComplexInput" to be an object, found: "NotVeryComplex". @ 5:30',
          ],
        );
      });

      test('variables with complex invalid default values', () {
        expect(
          port.errors(r'''
        query WithDefaultValues(
          $a: ComplexInput = { requiredField: 123, intField: "abc" }
        ) {
          dog { name }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: 123 @ 3:47',
            'Int cannot represent non-integer value: "abc" @ 3:62',
          ],
        );
      });

      test('complex variables missing required field', () {
        expect(
          port.errors(r'''
        query MissingRequiredField($a: ComplexInput = {intField: 3}) {
          dog { name }
        }
      '''),
          [
            'Expected value of type "ComplexInput" to include required field "requiredField", found: { intField: 3 }. @ 2:55',
          ],
        );
      });

      test('list variables with invalid item', () {
        expect(
          port.errors(r'''
        query InvalidItem($a: [String] = ["one", 2]) {
          dog { name }
        }
      '''),
          [
            'String cannot represent a non string value: 2 @ 2:50',
          ],
        );
      });
    });
  });
}
