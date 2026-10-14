import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import 'character_class.dart';
import 'source_reader.dart';
import 'token.dart';
import 'token_kind.dart';
import 'token_source.dart';

/// Turns a schema coordinate into tokens: names, `.`, `(`, `)`, `:` and
/// `@` (September2025 §2 "Schema Coordinates").
///
/// A coordinate has no ignored tokens, so white space, line terminators,
/// commas and comments are invalid characters here. Like `Lexer`, it never
/// throws: an invalid character becomes one [TokenKind.error] token and
/// one diagnostic with graphql-js's message, `Invalid character: " ".`
final class SchemaCoordinateLexer implements TokenSource {
  /// Creates a lexer of [source] that reports into [sink].
  SchemaCoordinateLexer(Source source, DiagnosticSink sink)
    : _reader = SourceReader(source, sink);

  final SourceReader _reader;
  int _position = 0;

  static const CharacterClass _classes = CharacterClass();

  static const Map<int, TokenKind> _punctuators = {
    0x28: .parenLeft,
    0x29: .parenRight,
    0x2e: .dot,
    0x3a: .colon,
    0x40: .at,
  };

  @override
  Source get source => _reader.source;

  /// Always false: a coordinate has no token limit.
  @override
  bool get isLimitReached => false;

  @override
  Token advance() {
    final token = _scan(_position);
    _position = token.end;
    return token;
  }

  Token _scan(int at) {
    final unit = _reader.unitAt(at);
    if (_punctuators[unit] case final kind?) {
      return Token(kind, at, at + 1);
    }
    if (unit < 0) {
      return Token(.eof, at, at);
    }
    return _classes.isNameStart(unit) ? _reader.name(at) : _invalid(at);
  }

  /// A lone surrogate is [DiagnosticCode.invalidCharacter], as in a
  /// document; any other character [DiagnosticCode.unexpectedCharacter].
  Token _invalid(int at) {
    final width = _reader.characterWidthAt(at);
    final end = at + (width == 0 ? 1 : width);
    final message = 'Invalid character: ${_reader.describe(at)}.';
    final DiagnosticCode code = width == 0
        ? .invalidCharacter
        : .unexpectedCharacter;
    _reader.report(code, message, at, end);
    return Token(.error, at, end);
  }
}
