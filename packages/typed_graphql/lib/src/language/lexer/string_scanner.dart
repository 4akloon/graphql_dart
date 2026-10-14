import 'escape_reader.dart';
import 'source_reader.dart';
import 'token.dart';

/// Scans a quoted `StringValue` (spec §2.9.4) and decodes its escapes.
final class StringScanner {
  /// Creates a scanner of the text of [reader].
  StringScanner(this.reader) : _escapes = EscapeReader(reader);

  /// The text and the sink.
  final SourceReader reader;

  final EscapeReader _escapes;

  static const int _quote = 0x22;
  static const int _backslash = 0x5c;

  /// The string that starts with the quote at [start], or an error token
  /// over the string after one diagnostic.
  Token scan(int start) {
    final value = StringBuffer();
    var chunk = start + 1;
    var position = start + 1;
    while (true) {
      switch (reader.unitAt(position)) {
        case _quote:
          value.write(reader.slice(chunk, position));
          return Token(.string, start, position + 1, value: '$value');
        case _backslash:
          value.write(reader.slice(chunk, position));
          final escape = _escapes.read(position);
          final decoded = escape.value;
          if (decoded == null) {
            return _invalidEscape(start, position, escape.size);
          }
          value.write(decoded);
          position += escape.size;
          chunk = position;
        case final unit when _isLineEnd(unit):
          final end = position + (unit < 0 ? 0 : 1);
          const message = 'Unterminated string.';
          reader.report(.unterminatedString, message, position, end);
          return Token(.error, start, position);
        default:
          final width = reader.characterWidthAt(position);
          if (width == 0) {
            return _invalidCharacter(start, position);
          }
          position += width;
      }
    }
  }

  Token _invalidEscape(int start, int position, int size) {
    final text = reader.slice(position, position + size);
    final kind = reader.unitAt(position + 1) == 0x75 ? 'Unicode' : 'character';
    reader.report(
      .invalidEscapeSequence,
      'Invalid $kind escape sequence: "$text".',
      position,
      position + text.length,
    );
    return _skipRest(start, position + 1);
  }

  Token _invalidCharacter(int start, int position) {
    final character = reader.describe(position);
    reader.report(
      .invalidCharacter,
      'Invalid character within String: $character.',
      position,
      position + 1,
    );
    return _skipRest(start, position + 1);
  }

  /// An error token from [start] to the closing quote or the end of the
  /// line, without a second diagnostic.
  Token _skipRest(int start, int position) {
    var end = position;
    while (true) {
      switch (reader.unitAt(end)) {
        case _quote:
          return Token(.error, start, end + 1);
        case final unit when _isLineEnd(unit):
          return Token(.error, start, end);
        case _backslash:
          end += _isLineEnd(reader.unitAt(end + 1)) ? 1 : 2;
        default:
          end++;
      }
    }
  }

  static bool _isLineEnd(int unit) => unit < 0 || unit == 0x0a || unit == 0x0d;
}
