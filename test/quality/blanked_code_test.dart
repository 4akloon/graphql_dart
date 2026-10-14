import 'package:test/test.dart';

import 'blanked_code.dart';

void main() {
  test('blanks comments and keeps the quotes of strings', () {
    final code = BlankedCode(
      "final a = 'x { y'; // a { comment\n"
      '/* block /* nested */ still */ final b = "z";\n',
    );
    expect(code.lines, [
      "final a = '     ';${' ' * 15}",
      '${' ' * 31}final b = " ";',
      '',
    ]);
  });

  test('blanks interpolations, with the strings inside them', () {
    final code = BlankedCode(
      r"""final a = 'say ${'}'} and ${{1}.length} $b';""",
    );
    expect(code.lines.single, "final a = '${' ' * 31}';");
  });

  test('reads raw and multi-line strings', () {
    final code = BlankedCode("final a = r'\\';\nfinal b = '''\n{\n''';\n");
    expect(code.lines, [
      "final a = r' ';",
      "final b = '''",
      ' ',
      "''';",
      '',
    ]);
  });

  test('counts the brackets open at the start of each line', () {
    final code = BlankedCode('void f() {\n  g([\n    1,\n  ]);\n}\n');
    expect(code.depths, [0, 1, 3, 3, 1, 0]);
  });
}
