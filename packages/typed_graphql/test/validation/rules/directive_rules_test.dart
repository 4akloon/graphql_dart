import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes, the split of
// graphql-js's KnownDirectivesRule in two and the branches those suites do
// not reach.
void main() {
  final checked = Checked('''
directive @once on FIELD | QUERY
directive @many repeatable on FIELD
type Query { f: Int }
''');

  test('an unknown directive is GQL222', () {
    expect(checked.errors('{ f @nope }', [const KnownDirectivesRule()]), [
      '1:5 GQL222 Unknown directive "@nope".',
    ]);
  });

  test('a misplaced directive is GQL223', () {
    expect(
      checked.errors('query @skip(if: true) { f }', [
        const DirectivesInValidLocationsRule(),
      ]),
      ['1:7 GQL223 Directive "@skip" may not be used on QUERY.'],
    );
  });

  test('a repeated directive is GQL224', () {
    expect(
      checked.errors('{ f @once @once }', [
        const UniqueDirectivesPerLocationRule(),
      ]),
      [
        '1:5 GQL224 The directive "@once" can only be used once at this '
            'location.',
      ],
    );
  });

  test('KnownDirectivesRule leaves a misplaced directive alone', () {
    expect(
      checked.errors('query @skip(if: true) { f }', [
        const KnownDirectivesRule(),
      ]),
      isEmpty,
    );
  });

  test('DirectivesInValidLocationsRule leaves an unknown one alone', () {
    expect(
      checked.errors('{ f @nope }', [const DirectivesInValidLocationsRule()]),
      isEmpty,
    );
  });

  test('UniqueDirectivesPerLocationRule leaves an unknown one alone', () {
    expect(
      checked.errors('{ f @nope @nope }', [
        const UniqueDirectivesPerLocationRule(),
      ]),
      isEmpty,
    );
  });

  test('a repeatable directive may repeat', () {
    expect(
      checked.errors('{ f @many @many }', [
        const UniqueDirectivesPerLocationRule(),
      ]),
      isEmpty,
    );
  });

  test('a variable definition and a fragment spread have locations', () {
    expect(
      checked.errors(
        r'query ($v: Int @once) { ...F } fragment F on Query { f }',
        [const DirectivesInValidLocationsRule()],
      ),
      ['1:16 GQL223 Directive "@once" may not be used on VARIABLE_DEFINITION.'],
    );
  });

  test('the split rules together report in graphql-js order', () {
    expect(
      checked.errors('query @nope @skip(if: true) { f }', [
        const KnownDirectivesRule(),
        const DirectivesInValidLocationsRule(),
      ]),
      [
        '1:7 GQL222 Unknown directive "@nope".',
        '1:13 GQL223 Directive "@skip" may not be used on QUERY.',
      ],
    );
  });

  group('100000 directives on one field, built in code', () {
    const count = 100000;

    Document documentWith(String directive) => Document([
      OperationDefinition(
        OperationType.query,
        SelectionSet([
          Field(
            null,
            const Name('f'),
            directives: [
              for (var i = 0; i < count; i++) Directive(Name(directive)),
            ],
          ),
        ]),
      ),
    ]);

    test('a non-repeatable one is reported once per repeat', () {
      final diagnostics = const DocumentValidator(
        rules: [UniqueDirectivesPerLocationRule()],
        maxErrors: count,
      ).validate(checked.schema, documentWith('once')).diagnostics;
      expect(diagnostics, hasLength(count - 1));
    });

    test('a repeatable one is not reported', () {
      final diagnostics = const DocumentValidator(
        rules: [
          KnownDirectivesRule(),
          DirectivesInValidLocationsRule(),
          UniqueDirectivesPerLocationRule(),
        ],
      ).validate(checked.schema, documentWith('many')).diagnostics;
      expect(diagnostics, isEmpty);
    });
  });
}
