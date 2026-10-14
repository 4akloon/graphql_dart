// Ported from graphql-js src/language/__tests__/blockString-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const blockString = BlockString();

  String joinLines(List<String> lines) => lines.join('\n');

  group('dedentBlockStringLines', () {
    List<String> dedent(List<String> lines) => blockString.dedentLines(lines);

    test('handles empty string', () {
      expect(dedent(['']), <String>[]);
    });

    test('does not dedent first line', () {
      expect(dedent(['  a']), ['  a']);
      expect(dedent([' a', '  b']), [' a', 'b']);
    });

    test('removes minimal indentation length', () {
      expect(dedent(['', ' a', '  b']), ['a', ' b']);
      expect(dedent(['', '  a', ' b']), [' a', 'b']);
      expect(dedent(['', '  a', ' b', 'c']), ['  a', ' b', 'c']);
    });

    test('dedent both tab and space as single character', () {
      expect(dedent(['', '\ta', '          b']), [
        'a',
        '         b',
      ]);
      expect(dedent(['', '\t a', '          b']), [
        'a',
        '        b',
      ]);
      expect(dedent(['', ' \t a', '          b']), [
        'a',
        '       b',
      ]);
    });

    test('dedent do not take empty lines into account', () {
      expect(dedent(['a', '', ' b']), ['a', '', 'b']);
      expect(dedent(['a', ' ', '  b']), ['a', '', 'b']);
    });

    test('removes uniform indentation from a string', () {
      final lines = [
        '',
        '    Hello,',
        '      World!',
        '',
        '    Yours,',
        '      GraphQL.',
      ];
      expect(dedent(lines), [
        'Hello,',
        '  World!',
        '',
        'Yours,',
        '  GraphQL.',
      ]);
    });

    test('removes empty leading and trailing lines', () {
      final lines = [
        '',
        '',
        '    Hello,',
        '      World!',
        '',
        '    Yours,',
        '      GraphQL.',
        '',
        '',
      ];
      expect(dedent(lines), [
        'Hello,',
        '  World!',
        '',
        'Yours,',
        '  GraphQL.',
      ]);
    });

    test('removes blank leading and trailing lines', () {
      final lines = [
        '  ',
        '        ',
        '    Hello,',
        '      World!',
        '',
        '    Yours,',
        '      GraphQL.',
        '        ',
        '  ',
      ];
      expect(dedent(lines), [
        'Hello,',
        '  World!',
        '',
        'Yours,',
        '  GraphQL.',
      ]);
    });

    test('retains indentation from first line', () {
      final lines = [
        '    Hello,',
        '      World!',
        '',
        '    Yours,',
        '      GraphQL.',
      ];
      expect(dedent(lines), [
        '    Hello,',
        '  World!',
        '',
        'Yours,',
        '  GraphQL.',
      ]);
    });

    test('does not alter trailing spaces', () {
      final lines = [
        '               ',
        '    Hello,     ',
        '      World!   ',
        '               ',
        '    Yours,     ',
        '      GraphQL. ',
        '               ',
      ];
      expect(dedent(lines), [
        'Hello,     ',
        '  World!   ',
        '           ',
        'Yours,     ',
        '  GraphQL. ',
      ]);
    });
  });

  group('isPrintableAsBlockString', () {
    void expectPrintable(String value) {
      expect(blockString.isPrintable(value), true);
    }

    void expectNonPrintable(String value) {
      expect(blockString.isPrintable(value), false);
    }

    test('accepts valid strings', () {
      expectPrintable('');
      expectPrintable(' a');
      expectPrintable('\t"\n"');
      expectNonPrintable('\t"\n \n\t"');
    });

    test('rejects strings with only whitespace', () {
      expectNonPrintable(' ');
      expectNonPrintable('\t');
      expectNonPrintable('\t ');
      expectNonPrintable(' \t');
    });

    test('rejects strings with non-printable characters', () {
      expectNonPrintable('\x00');
      expectNonPrintable('a\x00b');
    });

    test('rejects strings with only empty lines', () {
      expectNonPrintable('\n');
      expectNonPrintable('\n\n');
      expectNonPrintable('\n\n\n');
      expectNonPrintable(' \n  \n');
      expectNonPrintable('\t\n\t\t\n');
    });

    test('rejects strings with carriage return', () {
      expectNonPrintable('\r');
      expectNonPrintable('\n\r');
      expectNonPrintable('\r\n');
      expectNonPrintable('a\rb');
    });

    test('rejects strings with leading empty lines', () {
      expectNonPrintable('\na');
      expectNonPrintable(' \na');
      expectNonPrintable('\t\na');
      expectNonPrintable('\n\na');
    });

    test('rejects strings with trailing empty lines', () {
      expectNonPrintable('a\n');
      expectNonPrintable('a\n ');
      expectNonPrintable('a\n\t');
      expectNonPrintable('a\n\n');
    });
  });

  group('printBlockString', () {
    void expectBlockString(String value, String readable, [String? minimize]) {
      expect(blockString.print(value), readable);
      expect(blockString.print(value, isMinified: true), minimize ?? readable);
    }

    test('does not escape characters', () {
      const value = '" \\ / \b \f \n \r \t';
      expectBlockString(value, '"""\n$value\n"""', '"""\n$value"""');
    });

    test('by default print block strings as single line', () {
      expectBlockString('one liner', '"""one liner"""');
    });

    test(
      'by default print block strings ending with triple quotation as multi-line',
      () {
        expectBlockString(
          'triple quotation """',
          '"""\ntriple quotation \\"""\n"""',
          r'"""triple quotation \""""""',
        );
      },
    );

    test('correctly prints single-line with leading space', () {
      expectBlockString(
        '    space-led string',
        '"""    space-led string"""',
      );
    });

    test(
      'correctly prints single-line with leading space and trailing quotation',
      () {
        expectBlockString(
          '    space-led value "quoted string"',
          '"""    space-led value "quoted string"\n"""',
        );
      },
    );

    test('correctly prints single-line with trailing backslash', () {
      expectBlockString(
        r'backslash \',
        '"""\nbackslash \\\n"""',
        '"""backslash \\\n"""',
      );
    });

    test('correctly prints multi-line with internal indent', () {
      expectBlockString(
        'no indent\n with indent',
        '"""\nno indent\n with indent\n"""',
        '"""\nno indent\n with indent"""',
      );
    });

    test('correctly prints string with a first line indentation', () {
      final value = joinLines([
        '    first  ',
        '  line     ',
        'indentation',
        '     string',
      ]);
      expectBlockString(
        value,
        joinLines([
          '"""',
          '    first  ',
          '  line     ',
          'indentation',
          '     string',
          '"""',
        ]),
        joinLines([
          '"""    first  ',
          '  line     ',
          'indentation',
          '     string"""',
        ]),
      );
    });
  });
}
