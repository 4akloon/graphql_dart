import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  /// Each token of [text] before the end as `kind start:end value`, then
  /// each diagnostic as `line:column id message`.
  List<String> lex(String text) {
    final sink = DiagnosticSink();
    final lexer = SchemaCoordinateLexer(Source(text), sink);
    return [
      for (
        var token = lexer.advance();
        token.kind != TokenKind.eof;
        token = lexer.advance()
      )
        '${token.kind.name} ${token.start}:${token.end}'
            '${token.value == null ? '' : ' ${token.value}'}',
      for (final diagnostic in sink.diagnostics)
        '${diagnostic.span?.location} ${diagnostic.code.id} '
            '${diagnostic.message}',
    ];
  }

  test('lexes names and the five coordinate punctuators', () {
    expect(lex('@a.b(c:)'), [
      'at 0:1',
      'name 1:2 a',
      'dot 2:3',
      'name 3:4 b',
      'parenLeft 4:5',
      'name 5:6 c',
      'colon 6:7',
      'parenRight 7:8',
    ]);
  });

  test('a name runs over letters, digits and underscores', () {
    expect(lex('__Type_2.f'), ['name 0:8 __Type_2', 'dot 8:9', 'name 9:10 f']);
  });

  test('white space is an invalid character, and lexing goes on', () {
    expect(lex('Foo .bar'), [
      'name 0:3 Foo',
      'error 3:4',
      'dot 4:5',
      'name 5:8 bar',
      '1:4 GQL001 Invalid character: " ".',
    ]);
  });

  test('a line terminator, a comma and a comment are invalid too', () {
    expect(lex('\na,#'), [
      'error 0:1',
      'name 1:2 a',
      'error 2:3',
      'error 3:4',
      '1:1 GQL001 Invalid character: U+000A.',
      '2:2 GQL001 Invalid character: ",".',
      '2:3 GQL001 Invalid character: "#".',
    ]);
  });

  test('document punctuators, digits and spreads are invalid', () {
    expect(lex(r'{1$...').where((line) => line.contains('GQL')), [
      '1:1 GQL001 Invalid character: "{".',
      '1:2 GQL001 Invalid character: "1".',
      r'1:3 GQL001 Invalid character: "$".',
    ]);
  });

  test('a supplementary character is one error token', () {
    expect(lex('a\u{1F600}'), [
      'name 0:1 a',
      'error 1:3',
      '1:2 GQL001 Invalid character: U+1F600.',
    ]);
  });

  test('a lone surrogate is GQL002, as in a document', () {
    expect(lex('\uDEAD'), [
      'error 0:1',
      '1:1 GQL002 Invalid character: U+DEAD.',
    ]);
  });

  test('the end is returned again on every later call', () {
    final lexer = SchemaCoordinateLexer(Source('a'), DiagnosticSink());
    lexer.advance();
    expect(lexer.advance().kind, TokenKind.eof);
    expect(lexer.advance().kind, TokenKind.eof);
    expect(lexer.isLimitReached, isFalse);
  });
}
