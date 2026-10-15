import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ProvidedRequiredArgumentsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const ProvidedRequiredArgumentsRule());

  group('Validate: Provided required arguments', () {
    test('ignores unknown arguments', () {
      expect(
        port.errors('''
      {
        dog {
          isHouseTrained(unknownArgument: true)
        }
      }
    '''),
        isEmpty,
      );
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

      test('No arg on non-null field with default', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            nonNullFieldWithDefault
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
      test('Missing one non-nullable argument', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req2: 2)
          }
        }
      '''),
          [
            'Argument "ComplicatedArgs.multipleReqs(req1:)" of type "Int!" is required, but it was not provided. @ 4:13',
          ],
        );
      });

      test('Missing multiple non-nullable arguments', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs
          }
        }
      '''),
          [
            'Argument "ComplicatedArgs.multipleReqs(req1:)" of type "Int!" is required, but it was not provided. @ 4:13',
            'Argument "ComplicatedArgs.multipleReqs(req2:)" of type "Int!" is required, but it was not provided. @ 4:13',
          ],
        );
      });

      test('Incorrect value and missing argument', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req1: "one")
          }
        }
      '''),
          [
            'Argument "ComplicatedArgs.multipleReqs(req2:)" of type "Int!" is required, but it was not provided. @ 4:13',
          ],
        );
      });
    });

    group('Directive arguments', () {
      test('ignores unknown directives', () {
        expect(
          port.errors('''
        {
          dog @unknown
        }
      '''),
          isEmpty,
        );
      });

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

      test('with directive with missing types', () {
        expect(
          port.errors('''
        {
          dog @include {
            name @skip
          }
        }
      '''),
          [
            'Argument "@include(if:)" of type "Boolean!" is required, but it was not provided. @ 3:15',
            'Argument "@skip(if:)" of type "Boolean!" is required, but it was not provided. @ 4:18',
          ],
        );
      });
    });
  });
}
