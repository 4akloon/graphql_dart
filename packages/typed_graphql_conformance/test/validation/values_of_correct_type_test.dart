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
    group('Valid values', () {
      test('Good int value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: 2)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good negative int value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: -2)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good boolean value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: true)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good string value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: "foo")
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good float value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: 1.1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good negative float value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: -1.1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Int into Float', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Int into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('String into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: "someIdString")
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good enum value', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: SIT)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Enum with undefined value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            enumArgField(enumArg: UNKNOWN)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Enum with null value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            enumArgField(enumArg: NO_FUR)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('null into nullable type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: null)
          }
        }
      '''),
          isEmpty,
        );

        expect(
          port.errors('''
        {
          dog(a: null, b: null, c:{ requiredField: true, intField: null }) {
            name
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Invalid String values', () {
      test('Int into String', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: 1)
          }
        }
      '''),
          [
            'String cannot represent a non string value: 1 @ 4:39',
          ],
        );
      });

      test('Float into String', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: 1.0)
          }
        }
      '''),
          [
            'String cannot represent a non string value: 1.0 @ 4:39',
          ],
        );
      });

      test('Boolean into String', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: true)
          }
        }
      '''),
          [
            'String cannot represent a non string value: true @ 4:39',
          ],
        );
      });

      test('Unquoted String into String', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: BAR)
          }
        }
      '''),
          [
            'String cannot represent a non string value: BAR @ 4:39',
          ],
        );
      });
    });

    group('Invalid Int values', () {
      test('String into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: "3")
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: "3" @ 4:33',
          ],
        );
      });

      test('Big Int into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: 829384293849283498239482938)
          }
        }
      '''),
          [
            'Int cannot represent non 32-bit signed integer value: 829384293849283498239482938 @ 4:33',
          ],
        );
      });

      test('Unquoted String into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: FOO)
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: FOO @ 4:33',
          ],
        );
      });

      test('Simple Float into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: 3.0)
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: 3.0 @ 4:33',
          ],
        );
      });

      test('Float into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: 3.333)
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: 3.333 @ 4:33',
          ],
        );
      });
    });

    group('Invalid Float values', () {
      test('String into Float', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: "3.333")
          }
        }
      '''),
          [
            'Float cannot represent non numeric value: "3.333" @ 4:37',
          ],
        );
      });

      test('Boolean into Float', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: true)
          }
        }
      '''),
          [
            'Float cannot represent non numeric value: true @ 4:37',
          ],
        );
      });

      test('Unquoted into Float', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: FOO)
          }
        }
      '''),
          [
            'Float cannot represent non numeric value: FOO @ 4:37',
          ],
        );
      });
    });

    group('Invalid Boolean value', () {
      test('Int into Boolean', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: 2)
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: 2 @ 4:41',
          ],
        );
      });

      test('Float into Boolean', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: 1.0)
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: 1.0 @ 4:41',
          ],
        );
      });

      test('String into Boolean', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: "true")
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: "true" @ 4:41',
          ],
        );
      });

      test('Unquoted into Boolean', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: TRUE)
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: TRUE @ 4:41',
          ],
        );
      });
    });

    group('Invalid ID value', () {
      test('Float into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: 1.0)
          }
        }
      '''),
          [
            'ID cannot represent a non-string and non-integer value: 1.0 @ 4:31',
          ],
        );
      });

      test('Boolean into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: true)
          }
        }
      '''),
          [
            'ID cannot represent a non-string and non-integer value: true @ 4:31',
          ],
        );
      });

      test('Unquoted into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: SOMETHING)
          }
        }
      '''),
          [
            'ID cannot represent a non-string and non-integer value: SOMETHING @ 4:31',
          ],
        );
      });
    });
  });
}
