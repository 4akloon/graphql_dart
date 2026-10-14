import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

// Spec section 9 of M4 (R0.3): documents 100000 items wide, parsed without
// the token limit. graphql-js is quadratic in some of them; every rule here
// must stay linear.
void main() {
  final checked = Checked('''
directive @tag(n: Int) repeatable on FIELD
type Query { node: Node }
type Node { name: String child: Node size(n: Int): Int }
''');
  const width = 100000;
  const limit = Duration(seconds: 10);

  DocumentValidationResult timed(String text) {
    final stopwatch = Stopwatch()..start();
    final result = checked.validate(text);
    expect(stopwatch.elapsed, lessThan(limit));
    return result;
  }

  String repeated(String Function(int index) item) =>
      List.generate(width, item).join(' ');

  test('100000 aliases are valid', () {
    final fields = repeated((index) => 'a$index: name');
    expect(timed('{ node { $fields } }'), isA<ValidDocument>());
  });

  test('100000 fields of one response name with two targets are '
      'conflicts up to the error limit', () {
    final fields = repeated(
      (index) => index.isEven ? 'x: name' : 'x: child { name }',
    );
    final result = timed('{ node { $fields } }') as InvalidDocument;
    expect(
      result.diagnostics.first.code,
      DiagnosticCode.overlappingFieldsCanBeMerged,
    );
  });

  test('100000 directives are valid', () {
    final directives = repeated((index) => '@tag(n: $index)');
    expect(timed('{ node { name $directives } }'), isA<ValidDocument>());
  });

  test('100000 repeated arguments are one diagnostic', () {
    final arguments = repeated((index) => 'n: $index');
    final result = timed('{ node { size($arguments) } }') as InvalidDocument;
    expect(
      result.diagnostics.single.code,
      DiagnosticCode.uniqueArgumentNames,
    );
  });

  test('100000 variables, each used once, are valid', () {
    final definitions = repeated((index) => '\$v$index: Int');
    final fields = repeated((index) => 's$index: size(n: \$v$index)');
    expect(
      timed('query Q($definitions) { node { $fields } }'),
      isA<ValidDocument>(),
    );
  });

  test('100000 operations are valid', () {
    final operations = repeated((index) => 'query Q$index { node { name } }');
    expect(timed(operations), isA<ValidDocument>());
  });

  test('100000 fragments spread side by side are valid', () {
    final spreads = repeated((index) => '...F$index');
    final fragments = repeated((index) => 'fragment F$index on Node { name }');
    expect(timed('{ node { $spreads } } $fragments'), isA<ValidDocument>());
  });

  test('1000 operations over one chain of 1000 fragments spend the step '
      'budget', () {
    // Each operation expands the whole chain: a million fields to merge.
    final operations = List.generate(
      1000,
      (index) => 'query Q$index { node { ...F0 } }',
    ).join(' ');
    final fragments = List.generate(
      1000,
      (index) =>
          'fragment F$index on Node { name ${index < 999 ? '...F${index + 1}' : ''} }',
    ).join(' ');
    final result = timed('$operations $fragments') as InvalidDocument;
    expect(result.diagnostics.single.code, DiagnosticCode.documentTooComplex);
  });

  test('fragments that expand to 2^60 fields spend the step budget', () {
    final fragments = List.generate(
      60,
      (index) =>
          'fragment F$index on Node { a: child { ...F${index + 1} } '
          'b: child { ...F${index + 1} } }',
    ).join(' ');
    final result = timed(
      '{ node { ...F0 } } $fragments fragment F60 on Node { name }',
    ) as InvalidDocument;
    expect(result.diagnostics.single.code, DiagnosticCode.documentTooComplex);
  });
}
