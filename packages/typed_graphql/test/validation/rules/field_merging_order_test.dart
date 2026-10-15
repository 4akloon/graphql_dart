import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// R3.3: skipping the second descent into a lone field must not change the
// order of the reports. `f` (an interface field) is alone in the object
// groups of both `B` and `A`; its descent runs first, and the descent of
// the later group, which put it on the stack first, must not take its place.
void main() {
  final checked = Checked('''
type Query { t: I }
interface I { f: U y: U z: U }
type A implements I { f: U y: U z: U }
type B implements I { f: U y: U z: U }
type U { p: Int q: Int }
''');

  test('the reports of a lone field come in the order of the walk', () {
    final result = checked.validate(
      '{ t { r: f { e: p e: q ...Q } ... on B { r: z { e: p ...Q } } '
      '... on A { r: y { e: q c: p } } } } '
      'fragment Q on U { c: p c: q e: q e: p }',
    ) as InvalidDocument;
    const suffix =
        ' Use different aliases on the fields to fetch both if this was '
        'intentional.';
    expect(
      result.diagnostics.map((d) => d.message.replaceFirst(suffix, '')),
      [
        'Fields "r" conflict because "f" and "z" are different fields.',
        'Fields "r" conflict because "f" and "y" are different fields.',
        'Fields "e" conflict because "p" and "q" are different fields.',
        'Fields "e" conflict because "p" and "q" are different fields.',
        'Fields "e" conflict because "q" and "p" are different fields.',
        'Fields "e" conflict because "p" and "q" are different fields.',
        'Fields "c" conflict because "p" and "q" are different fields.',
        'Fields "e" conflict because "q" and "p" are different fields.',
      ],
    );
  });
}
