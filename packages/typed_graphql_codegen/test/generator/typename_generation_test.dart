import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
interface Node { id: ID! }
type User implements Node { id: ID!, name: String }
type Bot implements Node { id: ID! }
type Query { me: User, node: Node }
''');

void main() {
  String generated(String document) {
    final parsed = CodegenConfig.parse(
      'schema: schema.graphql\n',
      path: 'typed_graphql.yaml',
    );
    if (parsed is! ConfigSuccess) fail('expected success, got $parsed');
    final result = ClientGenerator(parsed.config).generate(
      schema: _schema,
      documents: [ProjectFile('lib/a.graphql', document)],
    );
    expect(result.hasErrors, isFalse, reason: '${result.diagnostics}');
    return result.files.last.text;
  }

  test('a conditional __typename is a nullable member', () {
    expect(
      generated(r'''
query A($on: Boolean!) { me { __typename @include(if: $on) id } }
'''),
      contains('final String? typename;'),
    );
  });

  test('a conditional __typename does not replace the added one', () {
    expect(
      generated(r'''
query A($on: Boolean!) { me { __typename @include(if: $on) id } }
'''),
      contains(r'me{__typename@include(if:$on)id __typename}'),
    );
  });

  test('a conditional __typename on an abstract type still dispatches', () {
    expect(
      generated(r'''
query A($on: Boolean!) { node { __typename @include(if: $on) id ... on User { name } } }
'''),
      allOf(
        contains('sealed class ADataNode'),
        contains(
          r'node{__typename@include(if:$on)id ...on User{name}__typename}',
        ),
      ),
    );
  });
}
