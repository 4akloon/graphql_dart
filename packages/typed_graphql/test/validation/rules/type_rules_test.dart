import 'package:test/test.dart';
import 'package:typed_graphql/src/validation/rules/engine_ordered_sort.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes and the branches
// those suites do not reach.
void main() {
  final checked = Checked('''
type Query { name: String pet: Pet }
interface Pet { name: String }
type Dog implements Pet { name: String barks: Boolean }
input Filter { name: String }
''');

  List<String> idsOf(String text, ValidationRule rule) => [
    for (final diagnostic
        in checked
            .validate(text, validator: DocumentValidator(rules: [rule]))
            .diagnostics)
      diagnostic.code.id,
  ];

  test('an unknown type name is GQL212', () {
    expect(
      checked.errors('fragment F on Dg { name }', [const KnownTypeNamesRule()]),
      ['1:15 GQL212 Unknown type "Dg". Did you mean "Dog"?'],
    );
  });

  test('a type the document defines is known', () {
    expect(
      checked.errors('type Extra { a: String } fragment F on Extra { a }', [
        const KnownTypeNamesRule(),
      ]),
      isEmpty,
    );
  });

  test('suggestions can be turned off', () {
    final result = checked.validate(
      'fragment F on Dg { name }',
      validator: const DocumentValidator(
        rules: [KnownTypeNamesRule()],
        includesSuggestions: false,
      ),
    );
    expect(result.diagnostics.single.message, 'Unknown type "Dg".');
  });

  test('a fragment on a scalar is GQL213', () {
    expect(
      idsOf(
        'fragment F on String { name }',
        const FragmentsOnCompositeTypesRule(),
      ),
      ['GQL213'],
    );
  });

  test('an inline fragment on an input type is GQL213', () {
    expect(
      checked.errors('{ ... on Filter { name } }', [
        const FragmentsOnCompositeTypesRule(),
      ]),
      ['1:10 GQL213 Fragment cannot condition on non composite type "Filter".'],
    );
  });

  test('a variable of an object type is GQL226', () {
    expect(
      checked.errors(r'query ($p: [Dog!]) { name }', [
        const VariablesAreInputTypesRule(),
      ]),
      [r'1:12 GQL226 Variable "$p" cannot be non-input type "[Dog!]".'],
    );
  });

  test('a leaf field with a selection is GQL207', () {
    expect(
      checked.errors('{ name { length } }', [const ScalarLeafsRule()]),
      [
        '1:8 GQL207 Field "name" must not have a selection since type '
            '"String" has no subfields.',
      ],
    );
  });

  test('a composite field without a selection is GQL207', () {
    expect(
      checked.errors('{ pet }', [const ScalarLeafsRule()]),
      [
        '1:3 GQL207 Field "pet" of type "Pet" must have a selection of '
            'subfields. Did you mean "pet { ... }"?',
      ],
    );
  });

  test('a missing field is GQL205 with a type suggestion', () {
    expect(
      checked.errors('{ pet { barks } }', [const FieldsOnCorrectTypeRule()]),
      [
        '1:9 GQL205 Cannot query field "barks" on type "Pet". Did you mean '
            'to use an inline fragment on "Dog"?',
      ],
    );
  });

  test('a missing field suggests a close field name', () {
    expect(
      checked.errors('{ nam }', [const FieldsOnCorrectTypeRule()]),
      [
        '1:3 GQL205 Cannot query field "nam" on type "Query". Did you mean "name"?',
      ],
    );
  });

  test('a meta-field is a field of every composite type', () {
    expect(
      checked.errors('{ __typename pet { __typename } }', [
        const FieldsOnCorrectTypeRule(),
      ]),
      isEmpty,
    );
  });

  test('a field below an unknown type is left to KnownTypeNames', () {
    expect(
      checked.errors('{ ... on Nope { missing } }', [
        const FieldsOnCorrectTypeRule(),
      ]),
      isEmpty,
    );
  });

  group('EngineOrderedSort', () {
    int byValue(int a, int b) => a - b;

    test('sorts by a total order like List.sort', () {
      final items = [5, 3, 9, 1, 7, 3, 8, 2];
      expect(
        EngineOrderedSort<int>(byValue).sorted(items),
        [...items]..sort(),
      );
    });

    test('reverses a strictly descending leading run', () {
      expect(EngineOrderedSort<int>(byValue).sorted([9, 5, 2, 7]), [
        2,
        5,
        7,
        9,
      ]);
    });

    test('keeps equal items in their order', () {
      final pairs = [(1, 'a'), (0, 'b'), (1, 'c'), (0, 'd')];
      expect(
        EngineOrderedSort<(int, String)>(
          (a, b) => a.$1 - b.$1,
        ).sorted(pairs),
        [(0, 'b'), (0, 'd'), (1, 'a'), (1, 'c')],
      );
    });

    test('a long list is sorted too', () {
      final items = [for (var i = 0; i < 200; i++) (i * 37) % 101];
      expect(
        EngineOrderedSort<int>(byValue).sorted(items),
        [...items]..sort(),
      );
    });
  });
}
