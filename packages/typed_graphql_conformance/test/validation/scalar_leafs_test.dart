import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ScalarLeafsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const ScalarLeafsRule());

  group('Validate: Scalar leafs', () {
    test('valid scalar selection', () {
      expect(
        port.errors('''
      fragment scalarSelection on Dog {
        barks
      }
    '''),
        isEmpty,
      );
    });

    test('object type missing selection', () {
      expect(
        port.errors('''
      query directQueryOnObjectWithoutSubFields {
        human
      }
    '''),
        [
          'Field "human" of type "Human" must have a selection of subfields. Did you mean "human { ... }"? @ 3:9',
        ],
      );
    });

    test('object type having only one selection', () {
      // The parser rejects an empty selection set, so the document is built
      // in code, as graphql-js's test does.
      final document = Document([
        OperationDefinition(
          .query,
          SelectionSet([
            Field(null, const Name('human'), selectionSet: SelectionSet([])),
          ]),
        ),
      ]);
      final result = const DocumentValidator(
        rules: [ScalarLeafsRule()],
      ).validate(RulePort.testSchema, document);
      expect(
        [for (final diagnostic in result.diagnostics) diagnostic.message],
        [
          'Field "human" of type "Human" must have at least one field '
              'selected.',
        ],
      );
    });

    test('interface type missing selection', () {
      expect(
        port.errors('''
      {
        human { pets }
      }
    '''),
        [
          'Field "pets" of type "[Pet]" must have a selection of subfields. Did you mean "pets { ... }"? @ 3:17',
        ],
      );
    });

    test('valid scalar selection with args', () {
      expect(
        port.errors('''
      fragment scalarSelectionWithArgs on Dog {
        doesKnowCommand(dogCommand: SIT)
      }
    '''),
        isEmpty,
      );
    });

    test('scalar selection not allowed on Boolean', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedOnBoolean on Dog {
        barks { sinceWhen }
      }
    '''),
        [
          'Field "barks" must not have a selection since type "Boolean" has no subfields. @ 3:15',
        ],
      );
    });

    test('scalar selection not allowed on Enum', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedOnEnum on Cat {
        furColor { inHexDec }
      }
    '''),
        [
          'Field "furColor" must not have a selection since type "FurColor" has no subfields. @ 3:18',
        ],
      );
    });

    test('scalar selection not allowed with args', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedWithArgs on Dog {
        doesKnowCommand(dogCommand: SIT) { sinceWhen }
      }
    '''),
        [
          'Field "doesKnowCommand" must not have a selection since type "Boolean" has no subfields. @ 3:42',
        ],
      );
    });

    test('Scalar selection not allowed with directives', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedWithDirectives on Dog {
        name @include(if: true) { isAlsoHumanName }
      }
    '''),
        [
          'Field "name" must not have a selection since type "String" has no subfields. @ 3:33',
        ],
      );
    });

    test('Scalar selection not allowed with directives and args', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedWithDirectivesAndArgs on Dog {
        doesKnowCommand(dogCommand: SIT) @include(if: true) { sinceWhen }
      }
    '''),
        [
          'Field "doesKnowCommand" must not have a selection since type "Boolean" has no subfields. @ 3:61',
        ],
      );
    });
  });
}
