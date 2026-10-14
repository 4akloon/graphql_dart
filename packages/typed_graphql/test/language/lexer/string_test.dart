import 'package:test/test.dart';

import 'lexed.dart';

void main() {
  group('strings', () {
    test('decode simple and Unicode escapes', () {
      expect(
        Lexed(r'"a\"\\\/\b\f\n\r\t"').tokens.single.value,
        'a"\\/\b\f\n\r\t',
      );
      expect(
        Lexed(r'"A\u{1F600}😀"').tokens.single.value,
        'A\u{1F600}\u{1F600}',
      );
    });

    test('keep a supplementary character as it is', () {
      expect(Lexed('"\u{1F600}"').tokens.single.value, '\u{1F600}');
    });

    test('end at a line break with one error', () {
      final lexed = Lexed('"multi\nline');
      expect(lexed.errors, ['1:7 GQL004 Unterminated string.']);
      expect(lexed.described, ['error 0:6', 'name 7:11 line']);
    });

    test('report an unterminated string at the end', () {
      expect(Lexed('"no end quote').errors, [
        '1:14 GQL004 Unterminated string.',
      ]);
    });

    test('report the first bad escape and skip to the closing quote', () {
      final lexed = Lexed(r'"bad \z and \x" b');
      expect(lexed.errors, [
        r'1:6 GQL005 Invalid character escape sequence: "\z".',
      ]);
      expect(lexed.described, ['error 0:15', 'name 16:17 b']);
    });

    test('quote the text graphql-js quotes for bad Unicode escapes', () {
      final cases = {
        r'"bad \u1 esc"': r'"\u1 es"',
        r'"bad \u{FFFF"': r'"\u{FFFF""',
        r'"x \u{110000} esc"': r'"\u{110000}"',
        r'"x \u{12345678} esc"': r'"\u{12345678}"',
        r'"x \u{000000000} esc"': r'"\u{000000000"',
        r'"x \uD800\uD800 esc"': r'"\uD800"',
        r'"x \u{D83D}\u{DE00}"': r'"\u{D83D}"',
      };
      for (final MapEntry(key: text, value: quoted) in cases.entries) {
        expect(
          Lexed(text).diagnostics.single.message,
          'Invalid Unicode escape sequence: $quoted.',
          reason: text,
        );
      }
    });

    test('reject a lone surrogate', () {
      final lexed = Lexed('"bad \uDEAD"');
      expect(lexed.errors, [
        '1:6 GQL002 Invalid character within String: U+DEAD.',
      ]);
      expect(lexed.described, ['error 0:7']);
    });
  });

  group('block strings', () {
    test('compute the block string value', () {
      final token = Lexed('"""\n  a\n    b\n"""').tokens.single;
      expect(token.value, 'a\n  b');
      expect(token.end, 17);
    });

    test('unescape triple quotes only', () {
      expect(Lexed(r'"""a \""" \n b"""').tokens.single.value, r'a """ \n b');
    });

    test('report an unterminated block string at the end', () {
      expect(Lexed('"""').errors, ['1:4 GQL004 Unterminated string.']);
      expect(Lexed('""""').errors, ['1:5 GQL004 Unterminated string.']);
    });

    test('reject a lone surrogate and skip to the closing quotes', () {
      final lexed = Lexed('"""a\uD800b""" c');
      expect(lexed.errors, [
        '1:5 GQL002 Invalid character within String: U+D800.',
      ]);
      expect(lexed.described, ['error 0:9', 'name 10:11 c']);
    });
  });
}
