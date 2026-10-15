import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownArgumentNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const KnownArgumentNamesRule());

  group('Validate: Known argument names', () {
    test('single arg is known', () {
      expect(
        port.errors('''
      fragment argOnRequiredArg on Dog {
        doesKnowCommand(dogCommand: SIT)
      }
    '''),
        isEmpty,
      );
    });

    test('multiple args are known', () {
      expect(
        port.errors('''
      fragment multipleArgs on ComplicatedArgs {
        multipleReqs(req1: 1, req2: 2)
      }
    '''),
        isEmpty,
      );
    });

    test('ignores args of unknown fields', () {
      expect(
        port.errors('''
      fragment argOnUnknownField on Dog {
        unknownField(unknownArg: SIT)
      }
    '''),
        isEmpty,
      );
    });

    test('multiple args in reverse order are known', () {
      expect(
        port.errors('''
      fragment multipleArgsReverseOrder on ComplicatedArgs {
        multipleReqs(req2: 2, req1: 1)
      }
    '''),
        isEmpty,
      );
    });

    test('no args on optional arg', () {
      expect(
        port.errors('''
      fragment noArgOnOptionalArg on Dog {
        isHouseTrained
      }
    '''),
        isEmpty,
      );
    });

    test('args are known deeply', () {
      expect(
        port.errors('''
      {
        dog {
          doesKnowCommand(dogCommand: SIT)
        }
        human {
          pet {
            ... on Dog {
              doesKnowCommand(dogCommand: SIT)
            }
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('directive args are known', () {
      expect(
        port.errors('''
      {
        dog @skip(if: true)
      }
    '''),
        isEmpty,
      );
    });

    test('field args are invalid', () {
      expect(
        port.errors('''
      {
        dog @skip(unless: true)
      }
    '''),
        [
          'Unknown argument "unless" on directive "@skip". @ 3:19',
        ],
      );
    });

    test('directive without args is valid', () {
      expect(
        port.errors('''
      {
        dog @onField
      }
    '''),
        isEmpty,
      );
    });

    test('arg passed to directive without arg is reported', () {
      expect(
        port.errors('''
      {
        dog @onField(if: true)
      }
    '''),
        [
          'Unknown argument "if" on directive "@onField". @ 3:22',
        ],
      );
    });

    test('misspelled directive args are reported', () {
      expect(
        port.errors('''
      {
        dog @skip(iff: true)
      }
    '''),
        [
          'Unknown argument "iff" on directive "@skip". Did you mean "if"? @ 3:19',
        ],
      );
    });

    test('misspelled directive args are reported (no suggestions)', () {
      expect(
        port.errors('''
      {
        dog @skip(iff: true)
      }
    ''', hidesSuggestions: true),
        [
          'Unknown argument "iff" on directive "@skip". @ 3:19',
        ],
      );
    });

    test('invalid arg name', () {
      expect(
        port.errors('''
      fragment invalidArgName on Dog {
        doesKnowCommand(unknown: true)
      }
    '''),
        [
          'Unknown argument "unknown" on field "Dog.doesKnowCommand". @ 3:25',
        ],
      );
    });

    test('misspelled arg name is reported', () {
      expect(
        port.errors('''
      fragment invalidArgName on Dog {
        doesKnowCommand(DogCommand: true)
      }
    '''),
        [
          'Unknown argument "DogCommand" on field "Dog.doesKnowCommand". Did you mean "dogCommand"? @ 3:25',
        ],
      );
    });

    test('misspelled arg name is reported (no suggestions)', () {
      expect(
        port.errors('''
      fragment invalidArgName on Dog {
        doesKnowCommand(DogCommand: true)
      }
    ''', hidesSuggestions: true),
        [
          'Unknown argument "DogCommand" on field "Dog.doesKnowCommand". @ 3:25',
        ],
      );
    });

    test('unknown args amongst known args', () {
      expect(
        port.errors('''
      fragment oneGoodArgOneInvalidArg on Dog {
        doesKnowCommand(whoKnows: 1, dogCommand: SIT, unknown: true)
      }
    '''),
        [
          'Unknown argument "whoKnows" on field "Dog.doesKnowCommand". @ 3:25',
          'Unknown argument "unknown" on field "Dog.doesKnowCommand". @ 3:55',
        ],
      );
    });

    test('unknown args deeply', () {
      expect(
        port.errors('''
      {
        dog {
          doesKnowCommand(unknown: true)
        }
        human {
          pet {
            ... on Dog {
              doesKnowCommand(unknown: true)
            }
          }
        }
      }
    '''),
        [
          'Unknown argument "unknown" on field "Dog.doesKnowCommand". @ 4:27',
          'Unknown argument "unknown" on field "Dog.doesKnowCommand". @ 9:31',
        ],
      );
    });
  });
}
