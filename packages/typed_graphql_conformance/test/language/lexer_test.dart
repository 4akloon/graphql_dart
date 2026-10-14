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

  void expectName(String text, int start, int end, [int? line, int? column]) {
    expect(
      port.lexOne(text),
      contain({
        'kind': 'Name',
        'start': start,
        'end': end,
        'value': 'foo',
        if (line != null) ...{'line': line, 'column': column},
      }),
    );
  }

  group('Lexer', () {
    test('ignores BOM header', () {
      expectName('\uFEFF foo', 2, 5);
    });

    test('tracks line breaks', () {
      expectName('foo', 0, 3, 1, 1);
      expectName('\nfoo', 1, 4, 2, 1);
      expectName('\rfoo', 1, 4, 2, 1);
      expectName('\r\nfoo', 2, 5, 2, 1);
      expectName('\n\rfoo', 2, 5, 3, 1);
      expectName('\r\r\n\nfoo', 4, 7, 4, 1);
      expectName('\n\n\r\rfoo', 4, 7, 5, 1);
    });

    test('records line and column', () {
      expectName('\n \r\n \r  foo\n', 8, 11, 4, 3);
    });

    test('skips whitespace and comments', () {
      expectName('\n\n    foo\n\n\n', 6, 9);
      expectName('\t\tfoo\t\t', 2, 5);
      expectName('\n    #comment\n    foo#comment\n', 18, 21);
      expectName(',,,foo,,,', 3, 6);
    });

    test('reports unexpected characters', () {
      expectSyntaxError('.', 'Syntax Error: Unexpected character: ".".', 1, 1);
    });

    // Adapted: the printLocation source excerpt arrives in M2b, so only the message and the location are compared.
    test('errors respect whitespace', () {
      expectSyntaxError(
        '\n\n ~\n',
        'Syntax Error: Unexpected character: "~".',
        3,
        2,
      );
    });

    test('lexes numbers', () {
      void expectNumber(String text, String kind) {
        expect(
          port.lexOne(text),
          contain({
            'kind': kind,
            'start': 0,
            'end': text.length,
            'value': text,
          }),
        );
      }

      expectNumber('4', 'Int');
      expectNumber('4.123', 'Float');
      expectNumber('-4', 'Int');
      expectNumber('9', 'Int');
      expectNumber('0', 'Int');
      expectNumber('-4.123', 'Float');
      expectNumber('0.123', 'Float');
      expectNumber('123e4', 'Float');
      expectNumber('123E4', 'Float');
      expectNumber('123e-4', 'Float');
      expectNumber('123e+4', 'Float');
      expectNumber('-1.123e4', 'Float');
      expectNumber('-1.123E4', 'Float');
      expectNumber('-1.123e-4', 'Float');
      expectNumber('-1.123e+4', 'Float');
      expectNumber('-1.123e4567', 'Float');
    });

    test('lex reports useful number errors', () {
      expectSyntaxError(
        '00',
        'Syntax Error: Invalid number, unexpected digit after 0: "0".',
        1,
        2,
      );
      expectSyntaxError(
        '01',
        'Syntax Error: Invalid number, unexpected digit after 0: "1".',
        1,
        2,
      );
      expectSyntaxError(
        '01.23',
        'Syntax Error: Invalid number, unexpected digit after 0: "1".',
        1,
        2,
      );
      expectSyntaxError('+1', 'Syntax Error: Unexpected character: "+".', 1, 1);
      expectSyntaxError(
        '1.',
        'Syntax Error: Invalid number, expected digit but got: <EOF>.',
        1,
        3,
      );
      expectSyntaxError(
        '1e',
        'Syntax Error: Invalid number, expected digit but got: <EOF>.',
        1,
        3,
      );
      expectSyntaxError(
        '1E',
        'Syntax Error: Invalid number, expected digit but got: <EOF>.',
        1,
        3,
      );
      expectSyntaxError(
        '1.e1',
        'Syntax Error: Invalid number, expected digit but got: "e".',
        1,
        3,
      );
      expectSyntaxError(
        '.123',
        'Syntax Error: Invalid number, expected digit before ".", did you mean "0.123"?',
        1,
        1,
      );
      expectSyntaxError(
        '1.A',
        'Syntax Error: Invalid number, expected digit but got: "A".',
        1,
        3,
      );
      expectSyntaxError(
        '-A',
        'Syntax Error: Invalid number, expected digit but got: "A".',
        1,
        2,
      );
      expectSyntaxError(
        '1.0e',
        'Syntax Error: Invalid number, expected digit but got: <EOF>.',
        1,
        5,
      );
      expectSyntaxError(
        '1.0eA',
        'Syntax Error: Invalid number, expected digit but got: "A".',
        1,
        5,
      );
      expectSyntaxError(
        '1.0e"',
        'Syntax Error: Invalid number, expected digit but got: \'"\'.',
        1,
        5,
      );
      expectSyntaxError(
        '1.2e3e',
        'Syntax Error: Invalid number, expected digit but got: "e".',
        1,
        6,
      );
      expectSyntaxError(
        '1.2e3.4',
        'Syntax Error: Invalid number, expected digit but got: ".".',
        1,
        6,
      );
      expectSyntaxError(
        '1.23.4',
        'Syntax Error: Invalid number, expected digit but got: ".".',
        1,
        5,
      );
    });

    test('lex does not allow name-start after a number', () {
      expectSyntaxError(
        '0xF1',
        'Syntax Error: Invalid number, expected digit but got: "x".',
        1,
        2,
      );
      expectSyntaxError(
        '0b10',
        'Syntax Error: Invalid number, expected digit but got: "b".',
        1,
        2,
      );
      expectSyntaxError(
        '123abc',
        'Syntax Error: Invalid number, expected digit but got: "a".',
        1,
        4,
      );
      expectSyntaxError(
        '1_234',
        'Syntax Error: Invalid number, expected digit but got: "_".',
        1,
        2,
      );
      expectSyntaxError(
        '1\u00DF',
        'Syntax Error: Unexpected character: U+00DF.',
        1,
        2,
      );
      expectSyntaxError(
        '1.23f',
        'Syntax Error: Invalid number, expected digit but got: "f".',
        1,
        5,
      );
      expectSyntaxError(
        '1.234_5',
        'Syntax Error: Invalid number, expected digit but got: "_".',
        1,
        6,
      );
    });

    test('lexes punctuation', () {
      void expectPunctuator(String text) {
        expect(
          port.lexOne(text),
          contain({
            'kind': text,
            'start': 0,
            'end': text.length,
            'value': null,
          }),
        );
      }

      expectPunctuator('!');
      expectPunctuator(r'$');
      expectPunctuator('(');
      expectPunctuator(')');
      expectPunctuator('...');
      expectPunctuator(':');
      expectPunctuator('=');
      expectPunctuator('@');
      expectPunctuator('[');
      expectPunctuator(']');
      expectPunctuator('{');
      expectPunctuator('|');
      expectPunctuator('}');
    });

    test('lex reports useful unknown character error', () {
      expectSyntaxError(
        '..',
        'Syntax Error: Unexpected "..", did you mean "..."?',
        1,
        1,
      );
      expectSyntaxError('~', 'Syntax Error: Unexpected character: "~".', 1, 1);
      expectSyntaxError(
        '\u0000',
        'Syntax Error: Unexpected character: U+0000.',
        1,
        1,
      );
      expectSyntaxError(
        '\b',
        'Syntax Error: Unexpected character: U+0008.',
        1,
        1,
      );
      expectSyntaxError(
        '\u00AA',
        'Syntax Error: Unexpected character: U+00AA.',
        1,
        1,
      );
      expectSyntaxError(
        '\u0AAA',
        'Syntax Error: Unexpected character: U+0AAA.',
        1,
        1,
      );
      expectSyntaxError(
        '\u203B',
        'Syntax Error: Unexpected character: U+203B.',
        1,
        1,
      );
      expectSyntaxError(
        '\u{1F600}',
        'Syntax Error: Unexpected character: U+1F600.',
        1,
        1,
      );
      expectSyntaxError(
        '\uD83D\uDE00',
        'Syntax Error: Unexpected character: U+1F600.',
        1,
        1,
      );
      expectSyntaxError(
        '\uD800\uDC00',
        'Syntax Error: Unexpected character: U+10000.',
        1,
        1,
      );
      expectSyntaxError(
        '\uDBFF\uDFFF',
        'Syntax Error: Unexpected character: U+10FFFF.',
        1,
        1,
      );
      expectSyntaxError(
        '\uDEAD',
        'Syntax Error: Invalid character: U+DEAD.',
        1,
        1,
      );
    });

    test('lex reports useful information for dashes in names', () {
      expect(
        port.lexOne('a-b'),
        contain({'kind': 'Name', 'start': 0, 'end': 1, 'value': 'a'}),
      );
      expectSyntaxError(
        'a-b',
        'Syntax Error: Invalid number, expected digit but got: "b".',
        1,
        3,
      );
    });

    // Adapted: tokens are not linked, so only the kinds are compared, and there is no <SOF>.
    test('produces double linked list of tokens, including comments', () {
      expect(
        port.kindsWithComments('''
    {
      #comment
      field
    }
  '''),
        ['{', 'Comment', 'Name', '}', '<EOF>'],
      );
    });

    // Adapted: tokens are not linked, so the comment comes from Lexer(keepComments: true) instead of token.prev.
    test('lexes comments', () {
      expect(
        port.firstComment('# Comment'),
        contain({'kind': 'Comment', 'start': 0, 'end': 9, 'value': ' Comment'}),
      );
      expect(
        port.firstComment('# Comment\nAnother line'),
        contain({'kind': 'Comment', 'start': 0, 'end': 9, 'value': ' Comment'}),
      );
      expect(
        port.firstComment('# Comment\r\nAnother line'),
        contain({'kind': 'Comment', 'start': 0, 'end': 9, 'value': ' Comment'}),
      );
      expect(
        port.firstComment('# Comment \u{1F600}'),
        contain({
          'kind': 'Comment',
          'start': 0,
          'end': 12,
          'value': ' Comment \u{1F600}',
        }),
      );
      expectSyntaxError(
        '# Invalid surrogate \uDEAD',
        'Syntax Error: Invalid character: U+DEAD.',
        1,
        21,
      );
    });
  });

  group('isPunctuatorTokenKind', () {
    bool isPunctuatorToken(String text) => port.firstKind(text).isPunctuator;

    test('returns true for punctuator tokens', () {
      expect(isPunctuatorToken('!'), true);
      expect(isPunctuatorToken(r'$'), true);
      expect(isPunctuatorToken('&'), true);
      expect(isPunctuatorToken('('), true);
      expect(isPunctuatorToken(')'), true);
      expect(isPunctuatorToken('...'), true);
      expect(isPunctuatorToken(':'), true);
      expect(isPunctuatorToken('='), true);
      expect(isPunctuatorToken('@'), true);
      expect(isPunctuatorToken('['), true);
      expect(isPunctuatorToken(']'), true);
      expect(isPunctuatorToken('{'), true);
      expect(isPunctuatorToken('|'), true);
      expect(isPunctuatorToken('}'), true);
    });

    test('returns false for non-punctuator tokens', () {
      expect(isPunctuatorToken(''), false);
      expect(isPunctuatorToken('name'), false);
      expect(isPunctuatorToken('1'), false);
      expect(isPunctuatorToken('3.14'), false);
      expect(isPunctuatorToken('"str"'), false);
      expect(isPunctuatorToken('"""str"""'), false);
    });
  });
}
