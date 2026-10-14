import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('TokenKind', () {
    test('punctuators are the fifteen kinds from "!" to "}"', () {
      final punctuators = [
        for (final kind in TokenKind.values)
          if (kind.isPunctuator) kind.description,
      ];
      expect(punctuators, [
        '"!"',
        r'"$"',
        '"&"',
        '"("',
        '")"',
        '"."',
        '"..."',
        '":"',
        '"="',
        '"@"',
        '"["',
        '"]"',
        '"{"',
        '"|"',
        '"}"',
      ]);
    });

    test('the end of the document is described as <EOF>', () {
      expect(TokenKind.eof.description, '<EOF>');
      expect(TokenKind.eof.isPunctuator, isFalse);
    });
  });

  group('Token', () {
    test('a token with a value is described with the value in quotes', () {
      const token = Token(TokenKind.name, 0, 2, value: 'id');
      expect(token.description, 'Name "id"');
    });

    test('a punctuator is described by its kind alone', () {
      expect(const Token(TokenKind.braceLeft, 0, 1).description, '"{"');
    });
  });
}
