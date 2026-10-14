import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import 'block_string_scanner.dart';
import 'character_class.dart';
import 'number_scanner.dart';
import 'source_reader.dart';
import 'string_scanner.dart';
import 'token.dart';
import 'token_kind.dart';

/// Turns a [Source] into tokens, one per [advance] (spec §2.1).
///
/// The lexer never throws (R1.2): text that is no token becomes one
/// [TokenKind.error] token over the offending run and one diagnostic in
/// the sink, and scanning resumes after it. Ignored tokens are skipped;
/// comments are returned only when [keepComments] is set.
///
/// With [maxTokens], the token after the limit is replaced by one
/// [DiagnosticCode.tokenLimitExceeded] error, [isLimitReached] becomes
/// true and every later call returns [TokenKind.eof] (R1.6).
final class Lexer {
  /// Creates a lexer of [source] that reports into [sink].
  Lexer(
    Source source,
    DiagnosticSink sink, {
    bool keepComments = false,
    int? maxTokens,
  }) : this._(
         SourceReader(source, sink),
         keepComments: keepComments,
         maxTokens: maxTokens,
       );

  Lexer._(
    SourceReader reader, {
    required this.keepComments,
    required this.maxTokens,
  }) : _reader = reader,
       _numbers = NumberScanner(reader),
       _strings = StringScanner(reader),
       _blockStrings = BlockStringScanner(reader);

  /// Whether [advance] returns [TokenKind.comment] tokens.
  final bool keepComments;

  /// The most tokens [advance] returns, comments and the end not counted;
  /// null for no limit.
  final int? maxTokens;

  final SourceReader _reader;
  final NumberScanner _numbers;
  final StringScanner _strings;
  final BlockStringScanner _blockStrings;
  int _position = 0;
  int _tokenCount = 0;
  bool _isLimitReached = false;

  /// The tokens returned so far, comments and the end not counted.
  int get tokenCount => _tokenCount;

  /// Whether [maxTokens] was exceeded, so the document was not read to
  /// its end.
  bool get isLimitReached => _isLimitReached;

  static const CharacterClass _classes = CharacterClass();

  static const Map<int, TokenKind> _punctuators = {
    0x21: .bang,
    0x24: .dollar,
    0x26: .ampersand,
    0x28: .parenLeft,
    0x29: .parenRight,
    0x3a: .colon,
    0x3d: .equals,
    0x40: .at,
    0x5b: .bracketLeft,
    0x5d: .bracketRight,
    0x7b: .braceLeft,
    0x7c: .pipe,
    0x7d: .braceRight,
  };

  /// The next token; [TokenKind.eof] at the end, and again on every later
  /// call.
  Token advance() {
    if (_isLimitReached) {
      return Token(.eof, _position, _position);
    }
    var token = _scanFrom(_position);
    while (token.kind == .comment && !keepComments) {
      token = _scanFrom(token.end);
    }
    return _counted(token);
  }

  Token _counted(Token token) {
    if (token.kind == .eof || token.kind == .comment) {
      return token;
    }
    _tokenCount++;
    final limit = maxTokens;
    if (limit == null || _tokenCount <= limit) {
      return token;
    }
    _isLimitReached = true;
    _position = token.start;
    _reader.report(
      .tokenLimitExceeded,
      'Document contains more than $limit tokens. Parsing aborted.',
      token.start,
      token.end,
    );
    return Token(.eof, token.start, token.start);
  }

  Token _scanFrom(int offset) {
    final token = _scan(_skipIgnored(offset));
    _position = token.end;
    return token;
  }

  /// The offset of the first character from [offset] on that is not
  /// white space, a line terminator, a comma or a byte order mark.
  int _skipIgnored(int offset) {
    var position = offset;
    while (_isIgnored(_reader.unitAt(position))) {
      position++;
    }
    return position;
  }

  static bool _isIgnored(int unit) => switch (unit) {
    0xfeff || 0x09 || 0x20 || 0x2c || 0x0a || 0x0d => true,
    _ => false,
  };

  Token _scan(int at) {
    final unit = _reader.unitAt(at);
    if (_punctuators[unit] case final kind?) {
      return Token(kind, at, at + 1);
    }
    return switch (unit) {
      -1 => Token(.eof, at, at),
      0x23 => _comment(at),
      0x2e => _dot(at),
      0x22 when _reader.slice(at, at + 3) == '"""' => _blockStrings.scan(at),
      0x22 => _strings.scan(at),
      _ when _classes.isDigit(unit) || unit == 0x2d => _numbers.scan(at),
      _ when _classes.isNameStart(unit) => _name(at),
      _ => _unexpected(at),
    };
  }

  Token _name(int start) {
    var end = start + 1;
    while (_classes.isNameContinue(_reader.unitAt(end))) {
      end++;
    }
    return Token(.name, start, end, value: _reader.slice(start, end));
  }

  /// A comment runs to a line terminator or to a character that is not
  /// a source character, which the next token reports.
  Token _comment(int start) {
    var end = start + 1;
    while (_reader.unitAt(end) != 0x0a && _reader.unitAt(end) != 0x0d) {
      final width = _reader.characterWidthAt(end);
      if (width == 0) {
        break;
      }
      end += width;
    }
    return Token(.comment, start, end, value: _reader.slice(start + 1, end));
  }

  Token _dot(int at) {
    if (_reader.unitAt(at + 1) != 0x2e) {
      return _classes.isDigit(_reader.unitAt(at + 1))
          ? _leadingDot(at)
          : _unexpected(at);
    }
    if (_reader.unitAt(at + 2) == 0x2e) {
      return Token(.spread, at, at + 3);
    }
    const message = 'Unexpected "..", did you mean "..."?';
    _reader.report(.unexpectedCharacter, message, at, at + 2);
    return Token(.error, at, at + 2);
  }

  /// `.5`: a number without its integer part.
  Token _leadingDot(int at) {
    var end = at + 1;
    while (_classes.isDigit(_reader.unitAt(end))) {
      end++;
    }
    final digits = _reader.slice(at + 1, end);
    _reader.report(
      .invalidNumber,
      'Invalid number, expected digit before ".", did you mean "0.$digits"?',
      at,
      end,
    );
    return Token(.error, at, end);
  }

  Token _unexpected(int at) {
    final width = _reader.characterWidthAt(at);
    final character = _reader.describe(at);
    final end = at + (width == 0 ? 1 : width);
    if (_reader.unitAt(at) == 0x27) {
      const message =
          'Unexpected single quote character (\'), did you mean to use a '
          'double quote (")?';
      _reader.report(.unexpectedCharacter, message, at, end);
    } else if (width == 0) {
      final message = 'Invalid character: $character.';
      _reader.report(.invalidCharacter, message, at, end);
    } else {
      final message = 'Unexpected character: $character.';
      _reader.report(.unexpectedCharacter, message, at, end);
    }
    return Token(.error, at, end);
  }
}
