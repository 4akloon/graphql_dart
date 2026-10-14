import 'package:test/test.dart';

import 'blanked_code.dart';
import 'declaration_scanner.dart';

void main() {
  DeclarationScanner scan(String source) =>
      DeclarationScanner(BlankedCode(source));

  test('finds types, their members and top-level functions', () {
    final scanner = scan(
      'final class A(final int x) {\n'
      '  this;\n'
      '\n'
      '  /// Doc.\n'
      '  @override\n'
      '  int get y =>\n'
      '      x + 1;\n'
      '  static const z = 1;\n'
      '}\n'
      '\n'
      'void main() {}\n'
      'int helper(int a) => a;\n',
    );
    expect([for (final t in scanner.types) t.type.name], ['A']);
    expect(
      [for (final m in scanner.members) (m.name, m.start, m.end)],
      [('A.this', 1, 1), ('A.y', 5, 6), ('A.z', 7, 7)],
    );
    expect([for (final f in scanner.functions) f.name], ['main', 'helper']);
  });

  test('skips the parameters of a primary constructor and enum values', () {
    final scanner = scan(
      'enum E(\n'
      '  final int id,\n'
      ') {\n'
      '  a(1),\n'
      '  b(2);\n'
      '\n'
      '  bool get isA => this == a;\n'
      '}\n',
    );
    expect([for (final m in scanner.members) m.name], ['E.isA']);
  });

  test('tells constructors from methods and fields', () {
    final members = scan(
      'class A {\n'
      '  A(int a);\n'
      '  A.named(int a);\n'
      '  factory A.make() => A(1);\n'
      '  final List<({int a, int b})> items = [];\n'
      '  final void Function(int a) f = print;\n'
      '  void run() {}\n'
      '}\n',
    ).members;
    expect(
      [for (final m in members) (m.name, m.isCallable, m.isConstructor)],
      [
        ('A.new', true, true),
        ('A.named', true, true),
        ('A.make', true, true),
        ('A.items', false, false),
        ('A.f', false, false),
        ('A.run', true, false),
      ],
    );
  });
}
