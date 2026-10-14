import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const blockString = BlockString();

  group('valueOf', () {
    test('removes the common indentation and blank edge lines', () {
      const raw =
          '\n    Hello,\n      World!\n\n    Yours,\n      GraphQL.\n  ';
      expect(
        blockString.valueOf(raw),
        'Hello,\n  World!\n\nYours,\n  GraphQL.',
      );
    });

    test('treats CR LF and CR as line terminators', () {
      expect(blockString.valueOf('\r\n  a\r  b\r\n'), 'a\nb');
    });
  });

  group('dedentLines', () {
    test('keeps the indentation of the first line', () {
      expect(blockString.dedentLines([' a', '  b']), [' a', 'b']);
    });

    test('ignores blank lines when it measures the indentation', () {
      expect(blockString.dedentLines(['a', ' ', '  b']), ['a', '', 'b']);
    });

    test('an empty string has no lines', () {
      expect(blockString.dedentLines(['']), isEmpty);
    });
  });

  group('isPrintable', () {
    test('accepts plain text and the empty string', () {
      expect(blockString.isPrintable(''), isTrue);
      expect(blockString.isPrintable(' a'), isTrue);
    });

    test('rejects control characters and carriage returns', () {
      expect(blockString.isPrintable('a\x00b'), isFalse);
      expect(blockString.isPrintable('a\rb'), isFalse);
    });

    test('rejects leading or trailing empty lines and common indent', () {
      expect(blockString.isPrintable('\na'), isFalse);
      expect(blockString.isPrintable('a\n'), isFalse);
      expect(blockString.isPrintable('\t"\n \n\t"'), isFalse);
    });
  });

  group('print', () {
    test('prints a short value on one line', () {
      expect(blockString.print('one liner'), '"""one liner"""');
    });

    test('escapes triple quotes and puts them on their own lines', () {
      expect(blockString.print('a """'), '"""\na \\"""\n"""');
      expect(blockString.print('a """', isMinified: true), r'"""a \""""""');
    });

    test('a trailing backslash forces a trailing line break', () {
      expect(
        blockString.print(r'backslash \', isMinified: true),
        '"""backslash \\\n"""',
      );
    });

    test('a value with internal indentation starts on a new line', () {
      expect(
        blockString.print('no indent\n with indent', isMinified: true),
        '"""\nno indent\n with indent"""',
      );
    });
  });
}
