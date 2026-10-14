import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text, int maxDirectives) => checked.errors(text, [
    MaxDirectivesRule(maxDirectives: maxDirectives),
  ]);

  // The operation, a variable definition, a field and an inline fragment
  // have one directive each; the spread adds the two of the fragment.
  const text =
      r'query Q($v: Int = 1 @a) @b { a @c { ... @d { b } ...F } } '
      'fragment F on Query @e { b @f }';

  test('an operation at the limit is valid', () {
    expect(errors(text, 6), isEmpty);
  });

  test('a named operation one over reports', () {
    expect(errors(text, 5), [
      '1:1 GQL234 The operation "Q" has more than 5 directives.',
    ]);
  });

  test('an anonymous operation is named in the message', () {
    expect(errors('{ b @x b @y }', 1), [
      '1:1 GQL234 The anonymous operation has more than 1 directives.',
    ]);
  });

  test('each spread counts its fragment definition directives again', () {
    const twice = '{ ...F @s ...F } fragment F on Query @e { b }';
    expect(errors(twice, 3), isEmpty);
    expect(errors(twice, 2), hasLength(1));
  });

  test('a fragment cycle counts its edge as 0', () {
    expect(errors('{ ...F } fragment F on Query { b @x ...F }', 1), isEmpty);
  });

  test('a negative limit is a RangeError', () {
    expect(() => errors('{ b }', -1), throwsRangeError);
  });

  test('two operations report each on its own', () {
    expect(errors('query A { b @x } query B { b @x b @y }', 1), [
      '1:18 GQL234 The operation "B" has more than 1 directives.',
    ]);
  });
}
