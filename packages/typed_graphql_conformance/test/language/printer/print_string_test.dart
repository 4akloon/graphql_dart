// Ported from graphql-js src/language/__tests__/printString-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  // graphql-js's `printString` is what the printer writes for a string
  // value that is not a block string.
  String printString(String value) => const Printer().print(StringValue(value));

  group('printString', () {
    test('prints a simple string', () {
      expect(printString('hello world'), '"hello world"');
    });

    test('escapes quotes', () {
      expect(printString('"hello world"'), r'"\"hello world\""');
    });

    test('does not escape single quote', () {
      expect(printString("who's test"), '"who\'s test"');
    });

    test('escapes backslashes', () {
      expect(printString(r'escape: \'), r'"escape: \\"');
    });

    test('escapes well-known control chars', () {
      expect(printString('\b\f\n\r\t'), r'"\b\f\n\r\t"');
    });

    test('escapes zero byte', () {
      expect(printString('\x00'), r'"\u0000"');
    });

    test('does not escape space', () {
      expect(printString(' '), '" "');
    });

    test('does not escape non-ascii character', () {
      expect(printString('↻'), '"↻"');
    });

    test('does not escape supplementary character', () {
      expect(printString('\u{1f600}'), '"\u{1f600}"');
    });

    // Adapted in form only: a loop over the code units 0x00-0x9F builds the
    // input and the expectation instead of graphql-js's long literal.
    test('escapes all control chars', () {
      const named = {
        0x08: r'\b',
        0x09: r'\t',
        0x0A: r'\n',
        0x0C: r'\f',
        0x0D: r'\r',
        0x22: r'\"',
        0x5C: r'\\',
      };
      final input = StringBuffer();
      final expected = StringBuffer('"');
      for (var unit = 0; unit <= 0x9F; unit++) {
        input.writeCharCode(unit);
        final isControl = unit < 0x20 || (unit >= 0x7F && unit <= 0x9F);
        final hex = unit.toRadixString(16).toUpperCase().padLeft(4, '0');
        expected.write(
          named[unit] ?? (isControl ? '\\u$hex' : String.fromCharCode(unit)),
        );
      }
      expected.write('"');
      expect(printString(input.toString()), expected.toString());
    });
  });
}
