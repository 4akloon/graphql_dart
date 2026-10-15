import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js
// src/validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts
// (the main describe block, up to the deep conflicts); mapping/validation.csv says which tests
// are adapted or skipped, and why.
void main() {
  final port = RulePort(const OverlappingFieldsCanBeMergedRule());

  group('Validate: Overlapping fields can be merged', () {
    test('unique fields', () {
      expect(
        port.errors('''
      fragment uniqueFields on Dog {
        name
        nickname
      }
    '''),
        isEmpty,
      );
    });

    test('identical fields', () {
      expect(
        port.errors('''
      fragment mergeIdenticalFields on Dog {
        name
        name
      }
    '''),
        isEmpty,
      );
    });

    test('identical fields with identical args', () {
      expect(
        port.errors('''
      fragment mergeIdenticalFieldsWithIdenticalArgs on Dog {
        doesKnowCommand(dogCommand: SIT)
        doesKnowCommand(dogCommand: SIT)
      }
    '''),
        isEmpty,
      );
    });

    test('identical fields with identical directives', () {
      expect(
        port.errors('''
      fragment mergeSameFieldsWithSameDirectives on Dog {
        name @include(if: true)
        name @include(if: true)
      }
    '''),
        isEmpty,
      );
    });

    test('different args with different aliases', () {
      expect(
        port.errors('''
      fragment differentArgsWithDifferentAliases on Dog {
        knowsSit: doesKnowCommand(dogCommand: SIT)
        knowsDown: doesKnowCommand(dogCommand: DOWN)
      }
    '''),
        isEmpty,
      );
    });

    test('different directives with different aliases', () {
      expect(
        port.errors('''
      fragment differentDirectivesWithDifferentAliases on Dog {
        nameIfTrue: name @include(if: true)
        nameIfFalse: name @include(if: false)
      }
    '''),
        isEmpty,
      );
    });

    test('different skip/include directives accepted', () {
      // Note: Differing skip/include directives don't create an ambiguous return
      // value and are acceptable in conditions where differing runtime values
      // may have the same desired effect of including or skipping a field.
      expect(
        port.errors('''
      fragment differentDirectivesWithDifferentAliases on Dog {
        name @include(if: true)
        name @include(if: false)
      }
    '''),
        isEmpty,
      );
    });

    test('Same aliases with different field targets', () {
      expect(
        port.errors('''
      fragment sameAliasesWithDifferentFieldTargets on Dog {
        fido: name
        fido: nickname
      }
    '''),
        [
          'Fields "fido" conflict because "name" and "nickname" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('Same aliases allowed on non-overlapping fields', () {
      // This is valid since no object can be both a "Dog" and a "Cat", thus
      // these fields can never overlap.
      expect(
        port.errors('''
      fragment sameAliasesWithDifferentFieldTargets on Pet {
        ... on Dog {
          name
        }
        ... on Cat {
          name: nickname
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Alias masking direct field access', () {
      expect(
        port.errors('''
      fragment aliasMaskingDirectFieldAccess on Dog {
        name: nickname
        name
      }
    '''),
        [
          'Fields "name" conflict because "nickname" and "name" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('different args, second adds an argument', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        doesKnowCommand
        doesKnowCommand(dogCommand: HEEL)
      }
    '''),
        [
          'Fields "doesKnowCommand" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('different args, second missing an argument', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        doesKnowCommand(dogCommand: SIT)
        doesKnowCommand
      }
    '''),
        [
          'Fields "doesKnowCommand" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('different args, first has two, second missing one', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        doesKnowCommand(dogCommand: SIT, atExpertLevel: true)
        doesKnowCommand(dogCommand: SIT)
      }
    '''),
        [
          'Fields "doesKnowCommand" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('conflicting arg values', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        doesKnowCommand(dogCommand: SIT)
        doesKnowCommand(dogCommand: HEEL)
      }
    '''),
        [
          'Fields "doesKnowCommand" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('conflicting arg names', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        isAtLocation(x: 0)
        isAtLocation(y: 0)
      }
    '''),
        [
          'Fields "isAtLocation" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('allows different args where no conflict is possible', () {
      // This is valid since no object can be both a "Dog" and a "Cat", thus
      // these fields can never overlap.
      expect(
        port.errors('''
      fragment conflictingArgs on Pet {
        ... on Dog {
          name(surname: true)
        }
        ... on Cat {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    test('allows different order of args', () {
      const schema = '''
      type Query {
        someField(a: String, b: String): String
      }
    ''';

      // This is valid since arguments are unordered, see:
      // https://spec.graphql.org/draft/#sec-Language.Arguments.Arguments-are-unordered
      expect(
        port.withSchema(schema).errors('''
        {
          someField(a: null, b: null)
          someField(b: null, a: null)
        }
      '''),
        isEmpty,
      );
    });

    test('allows different order of input object fields in arg values', () {
      const schema = '''
      input SomeInput {
        a: String
        b: String
      }

      type Query {
        someField(arg: SomeInput): String
      }
    ''';

      // This is valid since input object fields are unordered, see:
      // https://spec.graphql.org/draft/#sec-Input-Object-Values.Input-object-fields-are-unordered
      expect(
        port.withSchema(schema).errors('''
        {
          someField(arg: { a: null, b: null })
          someField(arg: { b: null, a: null })
        }
      '''),
        isEmpty,
      );
    });

    test('encounters conflict in fragments', () {
      expect(
        port.errors('''
      {
        ...A
        ...B
      }
      fragment A on Type {
        x: a
      }
      fragment B on Type {
        x: b
      }
    '''),
        [
          'Fields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 7:9 10:9',
        ],
      );
    });

    test('reports each conflict once', () {
      expect(
        port.errors('''
      {
        f1 {
          ...A
          ...B
        }
        f2 {
          ...B
          ...A
        }
        f3 {
          ...A
          ...B
          x: c
        }
      }
      fragment A on Type {
        x: a
      }
      fragment B on Type {
        x: b
      }
    '''),
        [
          'Fields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 18:9 21:9',
          'Fields "x" conflict because "c" and "a" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 14:11 18:9',
          'Fields "x" conflict because "c" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 14:11 21:9',
        ],
      );
    });
  });
}
