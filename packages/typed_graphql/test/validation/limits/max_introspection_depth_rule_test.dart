import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text) =>
      checked.errors(text, const [MaxIntrospectionDepthRule()]);

  test('the code id is GQL236', () {
    expect(DiagnosticCode.maxIntrospectionDepthExceeded.id, 'GQL236');
  });

  test('two lists deep is valid, three reports at the field', () {
    expect(
      errors('{ __schema { types { fields { type { fields { n } } } } } }'),
      isEmpty,
    );
    expect(
      errors(
        '{ __schema { types { fields { type { interfaces { '
        'possibleTypes { n } } } } } } }',
      ),
      ['1:3 GQL236 Maximum introspection depth exceeded'],
    );
  });

  test('a fragment defined after its use counts', () {
    const text =
        '{ __type(name: "Query") { ...F } } '
        'fragment F on __Type { fields { type { fields { type { '
        'inputFields { n } } } } } }';
    expect(errors(text), ['1:3 GQL236 Maximum introspection depth exceeded']);
  });

  test('a cycle and an unknown fragment count 0', () {
    expect(
      errors(
        '{ __schema { ...F ...Missing } } fragment F on __Schema { ...F }',
      ),
      isEmpty,
    );
  });

  test('a 2^60-expanding fragment chain finishes fast', () {
    final fragments = [
      for (var index = 0; index < 60; index++)
        'fragment F$index on __Type { ...F${index + 1} ...F${index + 1} }',
      'fragment F60 on __Type { fields { fields { fields { n } } } }',
    ];
    final stopwatch = Stopwatch()..start();
    final result = errors(
      '{ __schema { types { ...F0 } } } ${fragments.join(' ')}',
    );
    expect(result, ['1:3 GQL236 Maximum introspection depth exceeded']);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('recommendedRules is the specified rules and this one', () {
    expect(DocumentValidator.recommendedRules, hasLength(31));
    expect(
      DocumentValidator.recommendedRules.last,
      isA<MaxIntrospectionDepthRule>(),
    );
  });

  test('__type with three lists on a path reports at the field', () {
    expect(
      errors(
        '{ __type(name: "Query") { fields { type { fields { type { '
        'fields { n } } } } } } }',
      ),
      ['1:3 GQL236 Maximum introspection depth exceeded'],
    );
  });

  test('a __schema under a plain field reports at its own position', () {
    expect(
      errors(
        '{ a { __schema { types { fields { type { fields { type { '
        'fields { n } } } } } } } } }',
      ),
      ['1:7 GQL236 Maximum introspection depth exceeded'],
    );
  });

  test('a __schema inside a reported __type is not reported again', () {
    expect(
      errors(
        '{ __type(name: "Query") { fields { type { fields { type { '
        'fields { n } } } } } __schema { types { fields { type { fields '
        '{ type { fields { n } } } } } } } } }',
      ),
      ['1:3 GQL236 Maximum introspection depth exceeded'],
    );
  });
}
