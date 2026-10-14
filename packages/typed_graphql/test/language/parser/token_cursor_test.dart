import 'package:test/test.dart';
import 'package:typed_graphql/src/language/parser/syntax_abort.dart';
import 'package:typed_graphql/src/language/parser/token_cursor.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  TokenCursor cursorOf(String text, DiagnosticSink sink) =>
      TokenCursor(Lexer(Source(text), sink), sink);

  test('lookahead reads the next token without consuming', () {
    final cursor = cursorOf('a b', DiagnosticSink());
    expect(cursor.lookahead().value, 'b');
    expect(cursor.token.value, 'a');
    cursor.advance();
    expect(cursor.token.value, 'b');
    expect(cursor.lastEnd, 1);
  });

  test('the balance counts consumed brackets, braces and parentheses', () {
    final cursor = cursorOf('{ ( [ ] ) }', DiagnosticSink());
    final balances = [
      for (var i = 0; i < 6; i++) (cursor..advance()).balance,
    ];
    expect(balances, [1, 2, 3, 2, 1, 0]);
  });

  test('a second failure at the same offset is not reported', () {
    final sink = DiagnosticSink();
    final cursor = cursorOf('x', sink);
    expect(() => cursor.expect(TokenKind.colon), throwsA(isA<SyntaxAbort>()));
    expect(cursor.unexpected, throwsA(isA<SyntaxAbort>()));
    expect(sink.diagnostics.single.message, 'Expected ":", found Name "x".');
  });

  test('a failure at an error token adds nothing to the lexer error', () {
    final sink = DiagnosticSink();
    final cursor = cursorOf('~', sink);
    expect(cursor.unexpected, throwsA(isA<SyntaxAbort>()));
    expect(sink.diagnostics.single.code, DiagnosticCode.unexpectedCharacter);
  });
}
