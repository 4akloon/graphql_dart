import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/dart_string_literal.dart';

void main() {
  const DartStringLiteral literal = DartStringLiteral();

  final Map<String, String> expected = <String, String>{
    'plain': "'plain'",
    '': "''",
    r'a\b': r"r'a\b'",
    r'$x': r"r'$x'",
    "it's": '"it\'s"',
    r"it's $x": 'r"it\'s \$x"',
    'say "hi" it\'s': '\'say "hi" it\\\'s\'',
    'a\nb': r"'a\nb'",
    'a\tb\rc': r"'a\tb\rc'",
    '\u0001': r"'\u{1}'",
    '\u007f': r"'\u{7F}'",
    r"\'": r'''r"\'"''',
    r'''\'"''': r"""'\\\'"'""",
    'x\n\$y': r"'x\n\$y'",
    '\u{D800}': r"'\u{D800}'",
    'a\u{DC00}': r"'a\u{DC00}'",
    '\u{1F600}': "'\u{1F600}'",
  };

  expected.forEach((value, text) {
    test('literal of ${value.codeUnits}', () {
      expect(literal.of(value), text);
    });
  });
}
