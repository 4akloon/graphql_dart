import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  test('a limit at the largest int does not wrap the cap', () {
    const largest = -1 >>> 1;
    expect(
      checked.errors('{ b @x b @y }', [
        const MaxDirectivesRule(maxDirectives: largest),
      ]),
      isEmpty,
    );
  });

  test('fragments that cycle measure the same on every run', () {
    const text =
        '{ ...A ...B } fragment A on Query { b @x ...B } '
        'fragment B on Query { b @y b @z ...A }';
    List<String> run() => checked.errors(text, [
      const MaxDirectivesRule(maxDirectives: 0),
    ]);
    // A cycle edge counts 0, and a fragment cut by it is memoised as it was
    // measured, so the answer depends on the order but never on the run.
    expect(run(), hasLength(1));
    expect(run(), run());
  });
}
