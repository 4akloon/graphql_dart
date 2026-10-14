import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes and the walks.
void main() {
  final checked = Checked('''
type Query { name: String }
type Subscription { a: String b: String }
''');

  test('a type definition in a document is GQL200', () {
    expect(
      checked.errors('{ name } type T { f: String }', [
        const ExecutableDefinitionsRule(),
      ]),
      ['1:10 GQL200 The "T" definition is not executable.'],
    );
  });

  test('an operation without a root type is GQL201', () {
    expect(
      checked.errors('mutation { name }', [const KnownOperationTypesRule()]),
      ['1:1 GQL201 The mutation operation is not supported by the schema.'],
    );
  });

  test('a repeated operation name is GQL202 at the first one', () {
    expect(
      checked.errors('query A { name } query A { name }', [
        const UniqueOperationNamesRule(),
      ]),
      ['1:7 GQL202 There can be only one operation named "A".'],
    );
  });

  test('an anonymous operation beside another is GQL203', () {
    expect(
      checked.errors('{ name } query A { name }', [
        const LoneAnonymousOperationRule(),
      ]),
      [
        '1:1 GQL203 This anonymous operation must be the only defined '
            'operation.',
      ],
    );
  });

  test('a second subscription field is GQL204', () {
    expect(
      checked.errors('subscription { a b }', [
        const SingleFieldSubscriptionsRule(),
      ]),
      [
        '1:18 GQL204 Anonymous Subscription must select only one top level '
            'field.',
      ],
    );
  });

  test('subscription fields are collected without recursion', () {
    // Built in code: the parser stops at its own depth limit first.
    var selections = <Selection>[Field(null, const Name('b'))];
    for (var i = 0; i < 100000; i++) {
      selections = [InlineFragment(null, SelectionSet(selections))];
    }
    final document = Document([
      OperationDefinition(
        OperationType.subscription,
        SelectionSet([Field(null, const Name('a')), ...selections]),
      ),
    ]);
    final result = const DocumentValidator(
      rules: [SingleFieldSubscriptionsRule()],
    ).validate(checked.schema, document);
    expect(
      result.diagnostics.single.code,
      DiagnosticCode.singleFieldSubscriptions,
    );
  });

  test('the specified rules start with the operation rules', () {
    expect(DocumentValidator.specifiedRules.take(5), [
      isA<ExecutableDefinitionsRule>(),
      isA<KnownOperationTypesRule>(),
      isA<UniqueOperationNamesRule>(),
      isA<LoneAnonymousOperationRule>(),
      isA<SingleFieldSubscriptionsRule>(),
    ]);
  });
}
