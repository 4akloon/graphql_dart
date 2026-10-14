import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import '../lexer/block_string.dart';
import '../lexer/lexer.dart';
import '../lexer/token.dart';
import '../lexer/token_kind.dart';

/// Removes insignificant characters from GraphQL text as graphql-js's
/// `stripIgnoredCharacters` does: no whitespace, commas or comments, a
/// space only between two tokens that would merge, and block strings
/// printed in their shortest form.
final class Minifier {
  /// Creates the minifier; it keeps no state.
  const Minifier();

  /// [text] without its ignored tokens.
  String minify(String text) {
    final lexer = Lexer(Source(text), DiagnosticSink(), maxTokens: null);
    final buffer = StringBuffer();
    var wasNonPunctuator = false;
    for (
      var token = lexer.advance();
      token.kind != TokenKind.eof;
      token = lexer.advance()
    ) {
      final isNonPunctuator = !token.kind.isPunctuator;
      // `1...` would lex as a bad number, so a spread is separated too.
      if (wasNonPunctuator && (isNonPunctuator || token.kind == .spread)) {
        buffer.write(' ');
      }
      buffer.write(switch (token) {
        Token(kind: .blockString, :final value?) => const BlockString().print(
          value,
          isMinified: true,
        ),
        _ => text.substring(token.start, token.end),
      });
      wasNonPunctuator = isNonPunctuator;
    }
    return buffer.toString();
  }
}
