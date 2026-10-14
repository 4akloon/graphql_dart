import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text) =>
      checked.errors(text, const [NoIntrospectionRule()]);

  test('the code id is GQL235', () {
    expect(DiagnosticCode.introspectionDisabled.id, 'GQL235');
  });

  test('__typename stays allowed', () {
    expect(errors('{ __typename a { __typename b } }'), isEmpty);
  });

  test('__schema and the fields below it report', () {
    expect(errors('{ __schema { queryType { name } } }'), [
      '1:3 GQL235 GraphQL introspection has been disabled, but the requested '
          'query contained the field "__schema".',
      '1:14 GQL235 GraphQL introspection has been disabled, but the '
          'requested query contained the field "queryType".',
    ]);
  });

  test('__type reports', () {
    expect(errors('{ __type(name: "Query") { name } }'), hasLength(1));
  });
}
