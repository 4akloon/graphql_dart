// Ported from graphql-js src/language/__tests__/lexer-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../support/contain.dart';
import '../support/lexer_port.dart';

void main() {
  const port = LexerPort();
  const contain = Contain();

  void expectSyntaxError(String text, String message, int line, int column) {
    expect(port.syntaxError(text), {
      'message': message,
      'locations': [
        {'line': line, 'column': column},
      ],
    });
  }

  group('Lexer', () {
    test('lexes strings', () {
      void expectString(String text, int end, String value) {
        expect(
          port.lexOne(text),
          contain({'kind': 'String', 'start': 0, 'end': end, 'value': value}),
        );
      }

      expectString('""', 2, '');
      expectString('"simple"', 8, 'simple');
      expectString('" white space "', 15, ' white space ');
      expectString(r'"quote \""', 10, 'quote "');
      expectString(r'"escaped \n\r\b\t\f"', 20, 'escaped \n\r\b\t\f');
      expectString(r'"slashes \\ \/"', 15, r'slashes \ /');
      expectString(
        '"unescaped unicode outside BMP \u{1F600}"',
        34,
        'unescaped unicode outside BMP \u{1F600}',
      );
      expectString(
        '"unescaped maximal unicode outside BMP \u{10FFFF}"',
        42,
        'unescaped maximal unicode outside BMP \u{10FFFF}',
      );
      expectString(r'"unicode \u1234\u5678\u90AB\uCDEF"', 34, 'unicode ሴ噸邫췯');
      expectString(
        r'"unicode \u{1234}\u{5678}\u{90AB}\u{CDEF}"',
        42,
        'unicode ሴ噸邫췯',
      );
      expectString(
        r'"string with unicode escape outside BMP \u{1F600}"',
        50,
        'string with unicode escape outside BMP \u{1F600}',
      );
      expectString(
        r'"string with minimal unicode escape \u{0}"',
        42,
        'string with minimal unicode escape \u0000',
      );
      expectString(
        r'"string with maximal unicode escape \u{10FFFF}"',
        47,
        'string with maximal unicode escape \u{10FFFF}',
      );
      expectString(
        r'"string with maximal minimal unicode escape \u{00000000}"',
        57,
        'string with maximal minimal unicode escape \u0000',
      );
      expectString(
        r'"string with unicode surrogate pair escape \uD83D\uDE00"',
        56,
        'string with unicode surrogate pair escape \u{1F600}',
      );
      expectString(
        r'"string with minimal surrogate pair escape \uD800\uDC00"',
        56,
        'string with minimal surrogate pair escape \u{10000}',
      );
      expectString(
        r'"string with maximal surrogate pair escape \uDBFF\uDFFF"',
        56,
        'string with maximal surrogate pair escape \u{10FFFF}',
      );
    });

    test('lex reports useful string errors', () {
      expectSyntaxError('"', 'Syntax Error: Unterminated string.', 1, 2);
      expectSyntaxError('"""', 'Syntax Error: Unterminated string.', 1, 4);
      expectSyntaxError('""""', 'Syntax Error: Unterminated string.', 1, 5);
      expectSyntaxError(
        '"no end quote',
        'Syntax Error: Unterminated string.',
        1,
        14,
      );
      expectSyntaxError(
        '\'single quotes\'',
        'Syntax Error: Unexpected single quote character (\'), did you mean to use a double quote (")?',
        1,
        1,
      );
      expectSyntaxError(
        '"bad surrogate \uDEAD"',
        'Syntax Error: Invalid character within String: U+DEAD.',
        1,
        16,
      );
      expectSyntaxError(
        '"bad high surrogate pair \uDEAD\uDEAD"',
        'Syntax Error: Invalid character within String: U+DEAD.',
        1,
        26,
      );
      expectSyntaxError(
        '"bad low surrogate pair \uD800\uD800"',
        'Syntax Error: Invalid character within String: U+D800.',
        1,
        25,
      );
      expectSyntaxError(
        '"multi\nline"',
        'Syntax Error: Unterminated string.',
        1,
        7,
      );
      expectSyntaxError(
        '"multi\rline"',
        'Syntax Error: Unterminated string.',
        1,
        7,
      );
      expectSyntaxError(
        r'"bad \z esc"',
        r'Syntax Error: Invalid character escape sequence: "\z".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \x esc"',
        r'Syntax Error: Invalid character escape sequence: "\x".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \u1 esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u1 es".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \u0XX1 esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u0XX1".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \uXXXX esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\uXXXX".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \uFXXX esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\uFXXX".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \uXXXF esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\uXXXF".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \u{} esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u{}".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \u{FXXX} esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u{FX".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \u{FFFF esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u{FFFF ".',
        1,
        6,
      );
      expectSyntaxError(
        r'"bad \u{FFFF"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u{FFFF"".',
        1,
        6,
      );
      expectSyntaxError(
        r'"too high \u{110000} esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u{110000}".',
        1,
        11,
      );
      expectSyntaxError(
        r'"way too high \u{12345678} esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u{12345678}".',
        1,
        15,
      );
      expectSyntaxError(
        r'"too long \u{000000000} esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u{000000000".',
        1,
        11,
      );
      expectSyntaxError(
        r'"bad surrogate \uDEAD esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\uDEAD".',
        1,
        16,
      );
      expectSyntaxError(
        r'"bad surrogate \u{DEAD} esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u{DEAD}".',
        1,
        16,
      );
      expectSyntaxError(
        r'"cannot use braces for surrogate pair \u{D83D}\u{DE00} esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\u{D83D}".',
        1,
        39,
      );
      expectSyntaxError(
        r'"bad high surrogate pair \uDEAD\uDEAD esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\uDEAD".',
        1,
        26,
      );
      expectSyntaxError(
        r'"bad low surrogate pair \uD800\uD800 esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\uD800".',
        1,
        25,
      );
      expectSyntaxError(
        '"cannot escape half a pair \uD83D\\uDE00 esc"',
        'Syntax Error: Invalid character within String: U+D83D.',
        1,
        28,
      );
      expectSyntaxError(
        '"cannot escape half a pair \\uD83D\uDE00 esc"',
        r'Syntax Error: Invalid Unicode escape sequence: "\uD83D".',
        1,
        28,
      );
      expectSyntaxError(
        r'"bad \uD83D\not an escape"',
        r'Syntax Error: Invalid Unicode escape sequence: "\uD83D".',
        1,
        6,
      );
    });

    test('lexes block strings', () {
      void expectBlockString(String text, int end, String value) {
        expect(
          port.lexOne(text),
          contain({
            'kind': 'BlockString',
            'start': 0,
            'end': end,
            'line': 1,
            'column': 1,
            'value': value,
          }),
        );
      }

      expectBlockString('""""""', 6, '');
      expectBlockString('"""simple"""', 12, 'simple');
      expectBlockString('""" white space """', 19, ' white space ');
      expectBlockString('"""contains " quote"""', 22, 'contains " quote');
      expectBlockString(
        r'"""contains \""" triple quote"""',
        32,
        'contains """ triple quote',
      );
      expectBlockString('"""multi\nline"""', 16, 'multi\nline');
      expectBlockString(
        '"""multi\rline\r\nnormalized"""',
        28,
        'multi\nline\nnormalized',
      );
      expectBlockString(
        r'"""unescaped \n\r\b\t\f\u1234"""',
        32,
        r'unescaped \n\r\b\t\f\u1234',
      );
      expectBlockString(
        '"""unescaped unicode outside BMP \u{1F600}"""',
        38,
        'unescaped unicode outside BMP \u{1F600}',
      );
      expectBlockString(r'"""slashes \\ \/"""', 19, r'slashes \\ \/');
      expectBlockString(
        '"""\n\n        spans\n          multiple\n            lines\n\n        """',
        68,
        'spans\n  multiple\n    lines',
      );
    });

    test('advance line after lexing multiline block string', () {
      expect(
        port.lexSecond(
          '"""\n\n        spans\n          multiple\n            lines\n\n        \n """ second_token',
        ),
        contain({
          'kind': 'Name',
          'start': 71,
          'end': 83,
          'line': 8,
          'column': 6,
          'value': 'second_token',
        }),
      );
      expect(
        port.lexSecond(
          '""" \nspans \r\nmultiple \n\rlines \n\n"""\n second_token',
        ),
        contain({
          'kind': 'Name',
          'start': 37,
          'end': 49,
          'line': 8,
          'column': 2,
          'value': 'second_token',
        }),
      );
    });

    test('lex reports useful block string errors', () {
      expectSyntaxError('"""', 'Syntax Error: Unterminated string.', 1, 4);
      expectSyntaxError(
        '"""no end quote',
        'Syntax Error: Unterminated string.',
        1,
        16,
      );
      expectSyntaxError(
        '"""contains invalid surrogate \uDEAD"""',
        'Syntax Error: Invalid character within String: U+DEAD.',
        1,
        31,
      );
    });
  });
}
