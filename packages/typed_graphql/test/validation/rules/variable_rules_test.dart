import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes, the branches those
// suites do not reach and the work on large documents.
void main() {
  final checked = Checked('''
type Query { f(a: Int, b: Int! = 1, c: Int!, o: One, l: [Int!]): Int }
input One @oneOf { x: Int, y: String }
''');

  test('a repeated variable name is GQL225', () {
    expect(
      checked.errors(
        r'query ($a: Int, $b: Int, $a: Int) { f(a: $a, c: 1) }',
        [
          const UniqueVariableNamesRule(),
        ],
      ),
      [r'1:9 GQL225 There can be only one variable named "$a".'],
    );
  });

  test('an undefined variable is GQL227', () {
    expect(
      checked.errors(r'query Q { f(c: $c) }', [
        const NoUndefinedVariablesRule(),
      ]),
      [r'1:16 GQL227 Variable "$c" is not defined by operation "Q".'],
    );
  });

  test('an unused variable is GQL228', () {
    expect(
      checked.errors(r'query ($c: Int) { f(c: 1) }', [
        const NoUnusedVariablesRule(),
      ]),
      [r'1:8 GQL228 Variable "$c" is never used.'],
    );
  });

  test('a variable used only in a fragment the operation spreads is used', () {
    expect(
      checked.errors(
        r'query ($c: Int!) { ...F } fragment F on Query { f(c: $c) }',
        [const NoUnusedVariablesRule(), const NoUndefinedVariablesRule()],
      ),
      isEmpty,
    );
  });

  test('a variable of the wrong type is GQL229', () {
    expect(
      checked.errors(r'query ($c: String) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      [
        r'1:8 GQL229 Variable "$c" of type "String" used in position '
            'expecting type "Int!".',
      ],
    );
  });

  test('a nullable variable with a default fits a non-null position', () {
    expect(
      checked.errors(r'query ($c: Int = 1) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('a nullable variable fits a non-null position with a default', () {
    expect(
      checked.errors(r'query ($b: Int) { f(b: $b, c: 1) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('a null default does not make a nullable variable non-null', () {
    expect(
      checked.errors(r'query ($c: Int = null) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      hasLength(1),
    );
  });

  test('a nullable variable for a @oneOf field is GQL229', () {
    expect(
      checked.errors(r'query ($x: Int) { f(c: 1, o: {x: $x}) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      [
        r'1:8 GQL229 Variable "$x" is of type "Int" but must be non-nullable '
            'to be used for OneOf Input Object "One".',
      ],
    );
  });

  test('a non-null variable for a @oneOf field is allowed', () {
    expect(
      checked.errors(r'query ($x: Int!) { f(c: 1, o: {x: $x}) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('a variable of an unknown type is left to KnownTypeNamesRule', () {
    expect(
      checked.errors(r'query ($c: Nope) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('the last of two definitions of one name is the one checked', () {
    expect(
      checked.errors(r'query ($c: String, $c: Int!) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('errors of an operation come before those of the next', () {
    expect(
      checked.errors(r'query A { f(c: $x) } query B { f(c: $y) }', [
        const NoUndefinedVariablesRule(),
      ]),
      [
        r'1:16 GQL227 Variable "$x" is not defined by operation "A".',
        r'1:37 GQL227 Variable "$y" is not defined by operation "B".',
      ],
    );
  });

  group('100000 variables, built in code', () {
    const count = 100000;

    // The parser limits the size of a document.
    Document document({required bool isDefined, required bool isUsed}) =>
        Document([
          OperationDefinition(
            OperationType.query,
            SelectionSet([
              if (isUsed)
                for (var i = 0; i < count; i++)
                  Field(
                    Name('x$i'),
                    const Name('f'),
                    arguments: [
                      Argument(const Name('a'), Variable(Name('v$i'))),
                    ],
                  )
              else
                Field(null, const Name('f')),
            ]),
            variableDefinitions: [
              if (isDefined)
                for (var i = 0; i < count; i++)
                  VariableDefinition(
                    Variable(Name('v$i')),
                    const NamedType(Name('Int')),
                  ),
            ],
          ),
        ]);

    List<Diagnostic> run(Document document, ValidationRule rule) =>
        DocumentValidator(
          rules: [rule],
          maxErrors: count,
        ).validate(checked.schema, document).diagnostics;

    test('declared and used raise no error', () {
      final valid = document(isDefined: true, isUsed: true);
      expect(run(valid, const UniqueVariableNamesRule()), isEmpty);
      expect(run(valid, const NoUndefinedVariablesRule()), isEmpty);
      expect(run(valid, const NoUnusedVariablesRule()), isEmpty);
      expect(run(valid, const VariablesInAllowedPositionRule()), isEmpty);
    });

    test('used and not declared is one error each', () {
      final diagnostics = run(
        document(isDefined: false, isUsed: true),
        const NoUndefinedVariablesRule(),
      );
      expect(diagnostics, hasLength(count));
    });

    test('declared and not used is one error each', () {
      final diagnostics = run(
        document(isDefined: true, isUsed: false),
        const NoUnusedVariablesRule(),
      );
      expect(diagnostics, hasLength(count));
    });
  });

  test('a variable used at the end of a fragment chain of 100000', () {
    const length = 100000;
    // Built in code: the parser limits the size of a document.
    final document = Document([
      OperationDefinition(
        OperationType.query,
        SelectionSet([FragmentSpread(const Name('F0'))]),
        variableDefinitions: [
          VariableDefinition(
            const Variable(Name('c')),
            const NonNullType(NamedType(Name('Int'))),
          ),
        ],
      ),
      for (var i = 0; i < length; i++)
        FragmentDefinition(
          Name('F$i'),
          const NamedType(Name('Query')),
          SelectionSet([
            if (i + 1 < length)
              FragmentSpread(Name('F${i + 1}'))
            else
              Field(
                null,
                const Name('f'),
                arguments: [
                  const Argument(Name('c'), Variable(Name('c'))),
                ],
              ),
          ]),
        ),
    ]);
    final diagnostics = const DocumentValidator(
      rules: [
        NoUndefinedVariablesRule(),
        NoUnusedVariablesRule(),
        VariablesInAllowedPositionRule(),
      ],
    ).validate(checked.schema, document).diagnostics;
    expect(diagnostics, isEmpty);
  });

  test('the fragments of an operation are read in graphql-js order: the '
      'spreads of a set before those of its nested sets', () {
    final nested = Checked('type Query { name: String friend: Query }');
    expect(
      nested.errors(
        r'query Q { friend { ...B } ...A } '
        r'fragment A on Query { name @include(if: $a) } '
        r'fragment B on Query { name @include(if: $b) }',
        [const NoUndefinedVariablesRule()],
      ),
      [
        r'1:74 GQL227 Variable "$a" is not defined by operation "Q".',
        r'1:120 GQL227 Variable "$b" is not defined by operation "Q".',
      ],
    );
  });
}
