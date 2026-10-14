import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text, int maxDepth) =>
      checked.errors(text, [MaxDepthRule(maxDepth: maxDepth)]);

  test('an operation at the limit is valid', () {
    expect(errors('{ a { a { a { b } } } }', 4), isEmpty);
  });

  test('an anonymous operation one over reports its depth', () {
    expect(errors('{ a { a { a { b } } } }', 3), [
      '1:1 GQL232 The anonymous operation has a depth of 4, more than the '
          'maximum of 3.',
    ]);
  });

  test('a named operation is named in the message', () {
    expect(errors('query Q { a { b } }', 1), [
      '1:1 GQL232 The operation "Q" has a depth of 2, more than the maximum '
          'of 1.',
    ]);
  });

  test('inline fragments add no depth', () {
    expect(errors('{ a { ... on Query { a { b } } } }', 3), isEmpty);
  });

  test('a fragment defined after the operation adds its depth', () {
    expect(errors('{ a { ...F } } fragment F on Query { a { b } }', 2), [
      '1:1 GQL232 The anonymous operation has a depth of 3, more than the '
          'maximum of 2.',
    ]);
  });

  test('a fragment cycle does not hang and its edge adds nothing', () {
    expect(
      errors('{ a { ...F } } fragment F on Query { a { ...F } }', 2),
      isEmpty,
    );
  });

  test('a negative limit is a RangeError', () {
    expect(() => errors('{ b }', -1), throwsRangeError);
  });

  test('two operations report each on its own', () {
    expect(errors('query A { a { a { b } } } query B { a { a { b } } }', 2), [
      '1:1 GQL232 The operation "A" has a depth of 3, more than the maximum '
          'of 2.',
      '1:27 GQL232 The operation "B" has a depth of 3, more than the maximum '
          'of 2.',
    ]);
  });

  test('selections nested 100000 deep measure 100000', () {
    const depth = 100000;
    Selection field = Field(null, const Name('b'));
    for (var level = 1; level < depth; level++) {
      field = Field(null, const Name('a'), selectionSet: SelectionSet([field]));
    }
    final document = Document([
      OperationDefinition(.query, SelectionSet([field])),
    ]);
    List<Diagnostic> run(int limit) => DocumentValidator(
      rules: [MaxDepthRule(maxDepth: limit)],
    ).validate(checked.schema, document).diagnostics;

    expect(run(depth), isEmpty);
    expect(run(depth - 1).single.message, contains('a depth of $depth,'));
  });
}
