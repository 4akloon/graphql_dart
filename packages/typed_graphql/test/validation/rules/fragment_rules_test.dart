import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes and the branches
// those suites do not reach.
void main() {
  final checked = Checked('''
type Query { name: String dog: Dog pet: Pet }
interface Pet { name: String }
type Dog implements Pet { name: String }
type Cat implements Pet { name: String }
''');

  test('a repeated fragment name is GQL211', () {
    expect(
      checked.errors(
        'fragment A on Query { name } fragment A on Query { name }',
        [
          const UniqueFragmentNamesRule(),
        ],
      ),
      ['1:10 GQL211 There can be only one fragment named "A".'],
    );
  });

  test('an unknown fragment is GQL215', () {
    expect(
      checked.errors('{ ...Missing }', [const KnownFragmentNamesRule()]),
      ['1:6 GQL215 Unknown fragment "Missing".'],
    );
  });

  test('a fragment only a fragment spreads is used', () {
    expect(
      checked.errors(
        'query { ...A } fragment A on Query { ...B } '
        'fragment B on Query { name } fragment C on Query { name }',
        [const NoUnusedFragmentsRule()],
      ),
      ['1:74 GQL214 Fragment "C" is never used.'],
    );
  });

  test('a fragment that spreads itself is GQL216', () {
    expect(
      checked.errors('fragment A on Query { ...A } { ...A }', [
        const NoFragmentCyclesRule(),
      ]),
      ['1:23 GQL216 Cannot spread fragment "A" within itself.'],
    );
  });

  test('a fragment spread on an unrelated type is GQL217', () {
    expect(
      checked.errors('{ dog { ...OnCat } } fragment OnCat on Cat { name }', [
        const PossibleFragmentSpreadsRule(),
      ]),
      [
        '1:9 GQL217 Fragment "OnCat" cannot be spread here as objects of '
            'type "Dog" can never be of type "Cat".',
      ],
    );
  });

  test('an inline fragment on an unrelated type is GQL217', () {
    expect(
      checked.errors('{ dog { ... on Cat { name } } }', [
        const PossibleFragmentSpreadsRule(),
      ]),
      [
        '1:9 GQL217 Fragment cannot be spread here as objects of type "Dog" '
            'can never be of type "Cat".',
      ],
    );
  });

  test('an inline fragment without a type condition is possible', () {
    expect(
      checked.errors('{ dog { ... @include(if: true) { name } } }', [
        const PossibleFragmentSpreadsRule(),
      ]),
      isEmpty,
    );
  });

  group('a fragment chain of 100000', () {
    const length = 100000;

    // Built in code: the parser limits the size of a document.
    Document chain({required bool isCycle}) => Document([
      for (var i = 0; i < length; i++)
        FragmentDefinition(
          Name('F$i'),
          const NamedType(Name('Query')),
          SelectionSet([
            if (i + 1 < length)
              FragmentSpread(Name('F${i + 1}'))
            else if (isCycle)
              FragmentSpread(const Name('F0')),
          ]),
        ),
    ]);

    List<Diagnostic> cycleErrors(Document document) =>
        const DocumentValidator(rules: [NoFragmentCyclesRule()])
            .validate(checked.schema, document)
            .diagnostics;

    test('that closes on itself is one cycle, without recursion', () {
      final diagnostics = cycleErrors(chain(isCycle: true));
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.code, DiagnosticCode.noFragmentCycles);
      expect(
        diagnostics.single.message,
        startsWith('Cannot spread fragment "F0" within itself via "F1", '),
      );
    });

    test('that ends is valid, without recursion', () {
      expect(cycleErrors(chain(isCycle: false)), isEmpty);
    });
  });

  test('following spreads is charged to the step budget', () {
    final result = checked.validate(
      'fragment A on Query { ...B } fragment B on Query { ...A }',
      validator: const DocumentValidator(
        rules: [NoFragmentCyclesRule()],
        maxSteps: 1,
      ),
    );
    expect(result.diagnostics.map((diagnostic) => diagnostic.code), [
      DiagnosticCode.documentTooComplex,
    ]);
  });
}
