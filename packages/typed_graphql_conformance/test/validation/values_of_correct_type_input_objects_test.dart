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
    group('Valid input object value', () {
      test('Optional arg, despite required field in type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Partial object, only required', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: { requiredField: true })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Partial object, required field can be falsy', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: { requiredField: false })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Partial object, including required', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: { requiredField: true, intField: 4 })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Full object', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              requiredField: true,
              intField: 4,
              stringField: "foo",
              booleanField: false,
              stringListField: ["one", "two"]
            })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Full object with fields in different order', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              stringListField: ["one", "two"],
              booleanField: false,
              requiredField: true,
              stringField: "foo",
              intField: 4,
            })
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Valid oneOf input object value', () {
      test('Exactly one field', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: "abc" })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Exactly one non-nullable variable', () {
        expect(
          port.errors(r'''
        query ($string: String!) {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: $string })
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Invalid input object value', () {
      test('Partial object, missing required', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: { intField: 4 })
          }
        }
      '''),
          [
            'Expected value of type "ComplexInput" to include required field "requiredField", found: { intField: 4 }. @ 4:41',
          ],
        );
      });

      test('Partial object, invalid field type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              stringListField: ["one", 2],
              requiredField: true,
            })
          }
        }
      '''),
          [
            'String cannot represent a non string value: 2 @ 5:40',
          ],
        );
      });

      test('Partial object, null to non-null field', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              requiredField: true,
              nonNullField: null,
            })
          }
        }
      '''),
          [
            'Expected value of non-null type "Boolean!" not to be null. @ 6:29',
          ],
        );
      });

      test('Partial object, unknown field arg', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              requiredField: true,
              invalidField: "value"
            })
          }
        }
      '''),
          [
            'Expected value of type "ComplexInput" not to include unknown field "invalidField". Did you mean "intField"? Found: { requiredField: true, invalidField: "value" }. @ 6:15',
          ],
        );
      });

      test('Partial object, unknown field arg (no suggestions)', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              requiredField: true,
              invalidField: "value"
            })
          }
        }
      ''', hidesSuggestions: true),
          [
            'Expected value of type "ComplexInput" not to include unknown field "invalidField", found: { requiredField: true, invalidField: "value" }. @ 6:15',
          ],
        );
      });

      test('allows custom scalar to accept complex literals', () {
        final scalarPort = port.withSchema('''
          scalar Any
          type Query { anyArg(arg: Any): String }
        ''');

        expect(
          scalarPort.errors('''
          {
            test1: anyArg(arg: 123)
            test2: anyArg(arg: "abc")
            test3: anyArg(arg: [123, "abc"])
            test4: anyArg(arg: {deep: [123, "abc"]})
          }
        '''),
          isEmpty,
        );
      });
    });

    group('Invalid oneOf input object value', () {
      test('Invalid field type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: 2 })
          }
        }
      '''),
          [
            'String cannot represent a non string value: 2 @ 4:52',
          ],
        );
      });

      test('Exactly one null field', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: null })
          }
        }
      '''),
          [
            'Within OneOf Input Object type "OneOfInput", exactly one field must be specified, and the value for that field must be non-null. @ 4:37',
          ],
        );
      });

      test('More than one field', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: "abc", intField: 123 })
          }
        }
      '''),
          [
            'Within OneOf Input Object type "OneOfInput", exactly one field must be specified, and the value for that field must be non-null. @ 4:37',
          ],
        );
      });

      test('Unknown field does not add a oneOf error', () {
        expect(
          port.errors('''
          {
            complicatedArgs {
              oneOfArgField(oneOfArg: {
                stringField: "abc",
                invalidField: 123
              })
            }
          }
        '''),
          [
            'Expected value of type "OneOfInput" not to include unknown field "invalidField". Did you mean "intField"? Found: { stringField: "abc", invalidField: 123 }. @ 6:17',
          ],
        );
      });
    });
  });
}
