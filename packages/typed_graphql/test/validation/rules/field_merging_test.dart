import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// graphql-js's suite of this rule is ported in typed_graphql_conformance;
// these tests pin the code, the documented differences and the bounds.
void main() {
  final checked = Checked('''
type Query { dog: Dog pet: Pet name: String }
interface Pet { name: String }
type Dog implements Pet { name: String nickname: String mother: Dog father: Dog }
type Cat implements Pet { name: String meows: Boolean }
''');
  const rules = [OverlappingFieldsCanBeMergedRule()];

  // `dog { mother { mother { ... x: leaf } } }`, [depth] fields deep, built
  // in code: the parser's depth limit would refuse it as text.
  Field chain(int depth, String leaf) {
    var field = Field(const Name('x'), Name(leaf));
    for (var level = 0; level < depth; level++) {
      field = Field(
        null,
        const Name('mother'),
        selectionSet: SelectionSet([field]),
      );
    }
    return Field(null, const Name('dog'), selectionSet: SelectionSet([field]));
  }

  test('two fields with one response name and different targets are '
      'GQL206', () {
    expect(checked.errors('{ dog { x: name x: nickname } }', rules), [
      '1:9 GQL206 Fields "x" conflict because "name" and "nickname" are '
          'different fields. Use different aliases on the fields to fetch '
          'both if this was intentional.',
    ]);
  });

  test('a field is compared with the first field of each other class '
      'only', () {
    // graphql-js reports the father against both mothers; comparing each
    // field with the first of every other class keeps the work linear.
    expect(
      checked.errors(
        '{ dog { p: mother { name } p: mother { nickname } p: father { name } } }',
        rules,
      ),
      hasLength(1),
    );
  });

  test('a conflict 100000 fields deep is reported at the top pair', () {
    final document = Document([
      OperationDefinition(
        .query,
        SelectionSet([chain(100000, 'name'), chain(100000, 'nickname')]),
      ),
    ]);
    final diagnostics = const DocumentValidator(
      rules: rules,
    ).validate(checked.schema, document).diagnostics;
    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.message,
      endsWith(
        'subfields "x" conflict because "name" and "nickname" are '
        'different fields. Use different aliases on the fields to fetch '
        'both if this was intentional.',
      ),
    );
  });

  test('100000 fields with one response name merge in linear time', () {
    final fields = List.filled(100000, 'name').join(' ');
    final stopwatch = Stopwatch()..start();
    expect(checked.errors('{ dog { $fields } }', rules), isEmpty);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('fields that conflict only through a recursive fragment end', () {
    expect(
      checked.errors(
        '{ dog { ...F } } fragment F on Dog { x: name mother { ...F } }',
        rules,
      ),
      isEmpty,
    );
  });

  test('a conflict inside a fragment spread twice is reported once, at '
      'the fragment', () {
    expect(
      checked.errors(
        'query A { dog { ...F } } query B { dog { ...F } } '
        'fragment F on Dog { x: name x: nickname }',
        rules,
      ),
      [
        '1:71 GQL206 Fields "x" conflict because "name" and "nickname" are '
            'different fields. Use different aliases on the fields to fetch '
            'both if this was intentional.',
      ],
    );
  });

  test('a chain of fragments is merged once, not once per fragment', () {
    final fragments = List.generate(
      1000,
      (index) => 'fragment F$index on Dog { name ...F${index + 1} }',
    ).join(' ');
    final result = checked.validate(
      '{ dog { ...F0 } } $fragments fragment F1000 on Dog { name }',
      validator: const DocumentValidator(rules: rules, maxSteps: 10000),
    );
    expect(result, isA<ValidDocument>());
  });

  test('a document that expands beyond the step budget is GQL230', () {
    final result = checked.validate(
      '{ dog { ...A ...A } } fragment A on Dog { name nickname }',
      validator: const DocumentValidator(rules: rules, maxSteps: 2),
    );
    expect(result.diagnostics.single.code, DiagnosticCode.documentTooComplex);
  });
}
