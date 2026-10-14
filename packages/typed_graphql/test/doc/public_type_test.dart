import 'package:test/test.dart';

import 'public_type.dart';

void main() {
  const types = PublicTypes();

  test('finds classes of every modifier, enums, mixins and typedefs', () {
    final found = types.declaredIn('''
abstract interface class A {}
sealed class B {}
final class const C() {}
enum D { x }
mixin E {}
typedef F = int;
extension type G(int value) {}
''');
    expect(found.map((type) => type.name), ['A', 'B', 'C', 'D', 'E', 'F', 'G']);
  });

  test('skips private types', () {
    expect(
      types.declaredIn('class _Hidden {}\nclass Shown {}\n').single.name,
      'Shown',
    );
  });

  test('collects the doc comment, through annotations', () {
    final type = types
        .declaredIn(
          '/// First line.\n/// {@category schema}\n@immutable\nclass X {}\n',
        )
        .single;
    expect(type.documentation, ['First line.', '{@category schema}']);
    expect(type.line, 4);
  });

  test('a doc comment does not leak to the next declaration', () {
    final found = types.declaredIn('/// Doc.\nclass A {}\nclass B {}\n');
    expect(found.last.documentation, isEmpty);
  });
}
