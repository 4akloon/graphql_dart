import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'lexed.dart';

void main() {
  group('ignored tokens', () {
    test('skips the BOM, white space, commas and line terminators', () {
      expect(Lexed('﻿ ,\t\r\n\rfoo,').described, ['name 7:10 foo']);
    });

    test('drops comments unless asked to keep them', () {
      expect(Lexed('# hi\nfoo').described, ['name 5:8 foo']);
      expect(Lexed('# hi\r\nfoo', keepComments: true).described, [
        'comment 0:4  hi',
        'name 6:9 foo',
      ]);
    });

    test('an empty document is only the end', () {
      expect(Lexed('').tokens, isEmpty);
      expect(Lexed(' \n ').diagnostics, isEmpty);
    });
  });

  group('punctuators and names', () {
    test('lexes every punctuator', () {
      final kinds = [
        for (final token in Lexed(r'! $ & ( ) ... : = @ [ ] { | }').tokens)
          token.kind,
      ];
      expect(kinds, [
        for (final kind in TokenKind.values)
          if (kind.isPunctuator) kind,
      ]);
    });

    test('lexes names with digits and underscores', () {
      expect(Lexed('_a1 B_2').described, ['name 0:3 _a1', 'name 4:7 B_2']);
    });
  });

  group('numbers', () {
    test('keeps the lexeme of integers and floats', () {
      expect(Lexed('4 -0 9007199254740993 1.5e-3 0.0 2E+5').described, [
        'int 0:1 4',
        'int 2:4 -0',
        'int 5:21 9007199254740993',
        'float 22:28 1.5e-3',
        'float 29:32 0.0',
        'float 33:37 2E+5',
      ]);
    });

    test('rejects a leading zero', () {
      final lexed = Lexed('007');
      expect(lexed.errors, [
        '1:2 GQL003 Invalid number, unexpected digit after 0: "0".',
      ]);
      expect(lexed.described, ['error 0:3']);
    });

    test('rejects missing digits after "-", "." and the exponent', () {
      expect(Lexed('-').errors, [
        '1:2 GQL003 Invalid number, expected digit but got: <EOF>.',
      ]);
      expect(Lexed('1.').errors, [
        '1:3 GQL003 Invalid number, expected digit but got: <EOF>.',
      ]);
      expect(Lexed('1.0e').errors, [
        '1:5 GQL003 Invalid number, expected digit but got: <EOF>.',
      ]);
    });

    test('rejects a name or a dot glued to a number', () {
      final lexed = Lexed('1a 1.2.3 x');
      expect(lexed.errors, [
        '1:2 GQL003 Invalid number, expected digit but got: "a".',
        '1:7 GQL003 Invalid number, expected digit but got: ".".',
      ]);
      expect(lexed.described, ['error 0:2', 'error 3:8', 'name 9:10 x']);
    });

    test('rejects a number without its integer part', () {
      expect(Lexed('.123').errors, [
        '1:1 GQL003 Invalid number, expected digit before ".", '
            'did you mean "0.123"?',
      ]);
    });

    test('reports a dash in a name as a malformed number', () {
      expect(Lexed('a-b').errors, [
        '1:3 GQL003 Invalid number, expected digit but got: "b".',
      ]);
    });
  });

  group('unexpected characters', () {
    test('reports one error per character and resumes after it', () {
      final lexed = Lexed('a ~ b');
      expect(lexed.errors, ['1:3 GQL001 Unexpected character: "~".']);
      expect(lexed.described, ['name 0:1 a', 'error 2:3', 'name 4:5 b']);
    });

    test('suggests a spread for two dots and a double quote for one', () {
      expect(Lexed('..').errors, [
        '1:1 GQL001 Unexpected "..", did you mean "..."?',
      ]);
      expect(Lexed("'a'").errors.first, contains('did you mean to use a'));
    });

    test('names a control character and a supplementary character', () {
      expect(Lexed('\u0007').errors, [
        '1:1 GQL001 Unexpected character: U+0007.',
      ]);
      expect(Lexed('\u{1F600}').errors, [
        '1:1 GQL001 Unexpected character: U+1F600.',
      ]);
    });

    test('reports a lone surrogate as an invalid character', () {
      expect(Lexed('\uDEAD').errors, [
        '1:1 GQL002 Invalid character: U+DEAD.',
      ]);
    });

    test('a comment ends before a lone surrogate', () {
      final lexed = Lexed('# a\uD800', keepComments: true);
      expect(lexed.described, ['comment 0:3  a', 'error 3:4']);
    });
  });

  test('the end is returned again after the end', () {
    final lexer = Lexer(Source('a'), DiagnosticSink());
    lexer.advance();
    expect(lexer.advance().kind, TokenKind.eof);
    expect(lexer.advance().kind, TokenKind.eof);
  });
}
