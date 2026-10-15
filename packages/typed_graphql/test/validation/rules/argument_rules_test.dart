import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes and the branches
// those suites do not reach.
void main() {
  final checked = Checked('''
type Query { field(arg: String, needed: Int!): String plain: String }
directive @tag(label: String!) on FIELD
''');

  test('an unknown field argument is GQL208', () {
    expect(
      checked.errors('{ field(arg: "a", needed: 1, agr: "b") }', [
        const KnownArgumentNamesRule(),
      ]),
      [
        '1:30 GQL208 Unknown argument "agr" on field "Query.field". '
            'Did you mean "arg"?',
      ],
    );
  });

  test('an unknown directive argument is GQL208', () {
    expect(
      checked.errors('{ plain @tag(lable: "a", label: "b") }', [
        const KnownArgumentNamesRule(),
      ]),
      [
        '1:14 GQL208 Unknown argument "lable" on directive "@tag". '
            'Did you mean "label"?',
      ],
    );
  });

  test('a repeated argument is GQL209', () {
    expect(
      checked.errors('{ field(arg: "a", needed: 1, arg: "b") }', [
        const UniqueArgumentNamesRule(),
      ]),
      ['1:9 GQL209 There can be only one argument named "arg".'],
    );
  });

  test('a repeated argument relates to every other name', () {
    final result = checked.validate(
      '{ field(arg: "a", arg: "b", arg: "c") }',
      validator: const DocumentValidator(rules: [UniqueArgumentNamesRule()]),
    );
    expect(result.diagnostics.single.related, hasLength(2));
  });

  test('a repeated directive argument is GQL209', () {
    expect(
      checked.errors('{ plain @tag(label: "a", label: "b") }', [
        const UniqueArgumentNamesRule(),
      ]),
      ['1:14 GQL209 There can be only one argument named "label".'],
    );
  });

  test('a missing required field argument is GQL210', () {
    expect(
      checked.errors('{ field }', [const ProvidedRequiredArgumentsRule()]),
      [
        '1:3 GQL210 Argument "Query.field(needed:)" of type "Int!" is '
            'required, but it was not provided.',
      ],
    );
  });

  test('a missing required directive argument is GQL210', () {
    expect(
      checked.errors('{ plain @tag }', [const ProvidedRequiredArgumentsRule()]),
      [
        '1:9 GQL210 Argument "@tag(label:)" of type "String!" is required, '
            'but it was not provided.',
      ],
    );
  });

  test('an unknown directive is left to KnownDirectives', () {
    expect(
      checked.errors('{ plain @nope(x: 1) }', [
        const KnownArgumentNamesRule(),
        const ProvidedRequiredArgumentsRule(),
      ]),
      isEmpty,
    );
  });

  test('errors inside a field come before its missing argument', () {
    expect(
      checked.errors('{ field(arg: "a", other: 1) }', [
        const KnownArgumentNamesRule(),
        const ProvidedRequiredArgumentsRule(),
      ]),
      [startsWith('1:19 GQL208'), startsWith('1:3 GQL210')],
    );
  });
}
