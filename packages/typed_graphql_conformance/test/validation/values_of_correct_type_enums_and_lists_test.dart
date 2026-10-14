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
    group('Invalid Enum value', () {
      test('Int into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: 2)
          }
        }
      '''),
          [
            'Enum "DogCommand" cannot represent non-enum value: 2. @ 4:41',
          ],
        );
      });

      test('Float into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: 1.0)
          }
        }
      '''),
          [
            'Enum "DogCommand" cannot represent non-enum value: 1.0. @ 4:41',
          ],
        );
      });

      test('String into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: "SIT")
          }
        }
      '''),
          [
            'Enum "DogCommand" cannot represent non-enum value: "SIT". Did you mean the enum value "SIT"? @ 4:41',
          ],
        );
      });

      test('String into Enum (no suggestion)', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: "SIT")
          }
        }
      ''', hidesSuggestions: true),
          [
            'Enum "DogCommand" cannot represent non-enum value: "SIT". @ 4:41',
          ],
        );
      });

      test('Boolean into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: true)
          }
        }
      '''),
          [
            'Enum "DogCommand" cannot represent non-enum value: true. @ 4:41',
          ],
        );
      });

      test('Unknown Enum Value into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: JUGGLE)
          }
        }
      '''),
          [
            'Value "JUGGLE" does not exist in "DogCommand" enum. @ 4:41',
          ],
        );
      });

      test('Different case Enum Value into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: sit)
          }
        }
      '''),
          [
            'Value "sit" does not exist in "DogCommand" enum. Did you mean the enum value "SIT"? @ 4:41',
          ],
        );
      });

      test('Different case Enum Value into Enum (no suggestion)', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: sit)
          }
        }
      ''', hidesSuggestions: true),
          [
            'Value "sit" does not exist in "DogCommand" enum. @ 4:41',
          ],
        );
      });
    });

    group('Valid List value', () {
      test('Good list value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: ["one", null, "two"])
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Empty list value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: [])
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Null value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: null)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Single value into List', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: "one")
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Invalid List value', () {
      test('Incorrect item type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: ["one", 2])
          }
        }
      '''),
          [
            'String cannot represent a non string value: 2 @ 4:55',
          ],
        );
      });

      test('Single value of incorrect type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: 1)
          }
        }
      '''),
          [
            'String cannot represent a non string value: 1 @ 4:47',
          ],
        );
      });
    });

    group('Valid non-nullable value', () {
      test('Arg on optional arg', () {
        expect(
          port.errors('''
        {
          dog {
            isHouseTrained(atOtherHomes: true)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('No Arg on optional arg', () {
        expect(
          port.errors('''
        {
          dog {
            isHouseTrained
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple args', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req1: 1, req2: 2)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple args reverse order', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req2: 2, req1: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('No args on multiple optional', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOpts
          }
        }
      '''),
          isEmpty,
        );
      });

      test('One arg on multiple optional', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOpts(opt1: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Second arg on multiple optional', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOpts(opt2: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple required args on mixedList', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOptAndReq(req1: 3, req2: 4)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple required and one optional arg on mixedList', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOptAndReq(req1: 3, req2: 4, opt1: 5)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('All required and optional args on mixedList', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOptAndReq(req1: 3, req2: 4, opt1: 5, opt2: 6)
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Invalid non-nullable value', () {
      test('Incorrect value type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req2: "two", req1: "one")
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: "two" @ 4:32',
            'Int cannot represent non-integer value: "one" @ 4:45',
          ],
        );
      });

      test(
        'Incorrect value and missing argument (ProvidedRequiredArgumentsRule)',
        () {
          expect(
            port.errors('''
        {
          complicatedArgs {
            multipleReqs(req1: "one")
          }
        }
      '''),
            [
              'Int cannot represent non-integer value: "one" @ 4:32',
            ],
          );
        },
      );

      test('Null value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req1: null)
          }
        }
      '''),
          [
            'Expected value of non-null type "Int!" not to be null. @ 4:32',
          ],
        );
      });
    });
  });
}
