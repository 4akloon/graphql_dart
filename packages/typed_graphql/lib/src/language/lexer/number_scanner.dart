import 'character_class.dart';
import 'source_reader.dart';
import 'token.dart';
import 'token_kind.dart';

/// Scans an `IntValue` or a `FloatValue` (spec §2.9.1, §2.9.2), keeping
/// the lexeme as written.
final class NumberScanner {
  /// Creates a scanner of the text of [reader].
  NumberScanner(this.reader);

  /// The text and the sink.
  final SourceReader reader;

  static const CharacterClass _classes = CharacterClass();
  static const int _minus = 0x2d;
  static const int _plus = 0x2b;
  static const int _dot = 0x2e;
  static const int _zero = 0x30;

  /// The number that starts at [start] with a digit or `-`, or an error
  /// token over the malformed run after one diagnostic.
  Token scan(int start) {
    final position = reader.unitAt(start) == _minus ? start + 1 : start;
    if (reader.unitAt(position) == _zero) {
      if (_classes.isDigit(reader.unitAt(position + 1))) {
        final digit = reader.describe(position + 1);
        return _fail(start, position + 1, 'unexpected digit after 0: $digit');
      }
      return _afterInteger(start, position + 1);
    }
    return switch (_digitsFrom(position)) {
      final end? => _afterInteger(start, end),
      null => _expectedDigit(start, position),
    };
  }

  /// The rest of the number from [start] after its integer part, which
  /// ends at [position]: an optional fraction and exponent.
  Token _afterInteger(int start, int position) {
    var end = position;
    if (reader.unitAt(end) == _dot) {
      final fractionEnd = _digitsFrom(end + 1);
      if (fractionEnd == null) {
        return _expectedDigit(start, end + 1);
      }
      end = fractionEnd;
    }
    if (reader.unitAt(end) case 0x45 || 0x65) {
      final sign = reader.unitAt(end + 1);
      final digits = end + (sign == _plus || sign == _minus ? 2 : 1);
      final exponentEnd = _digitsFrom(digits);
      if (exponentEnd == null) {
        return _expectedDigit(start, digits);
      }
      end = exponentEnd;
    }
    final next = reader.unitAt(end);
    if (next == _dot || _classes.isNameStart(next)) {
      return _expectedDigit(start, end);
    }
    final kind = end == position ? TokenKind.int : TokenKind.float;
    return Token(kind, start, end, value: reader.slice(start, end));
  }

  /// The offset after the digits that start at [position], or null when
  /// there is no digit there.
  int? _digitsFrom(int position) {
    if (!_classes.isDigit(reader.unitAt(position))) {
      return null;
    }
    var end = position + 1;
    while (_classes.isDigit(reader.unitAt(end))) {
      end++;
    }
    return end;
  }

  Token _expectedDigit(int start, int at) =>
      _fail(start, at, 'expected digit but got: ${reader.describe(at)}');

  /// Reports `Invalid number, [problem].` at [at] and returns an error
  /// token from [start] over the rest of the malformed run.
  Token _fail(int start, int at, String problem) {
    reader.report(
      .invalidNumber,
      'Invalid number, $problem.',
      at,
      at + reader.characterWidthAt(at),
    );
    var end = at;
    while (_classes.isNameContinue(reader.unitAt(end)) ||
        reader.unitAt(end) == _dot) {
      end++;
    }
    return Token(.error, start, end);
  }
}
