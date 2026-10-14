import 'block_string.dart';
import 'source_reader.dart';
import 'token.dart';

/// Scans a block string, `"""..."""` (spec §2.9.4), and computes its
/// value with [BlockString].
final class BlockStringScanner {
  /// Creates a scanner of the text of [reader].
  BlockStringScanner(this.reader);

  /// The text and the sink.
  final SourceReader reader;

  static const BlockString _blockString = BlockString();

  /// The block string that starts with the `"""` at [start], or an error
  /// token over it after one diagnostic.
  Token scan(int start) {
    final raw = StringBuffer();
    var chunk = start + 3;
    var position = start + 3;
    while (!_isTripleQuoteAt(position)) {
      if (reader.unitAt(position) == 0x5c && _isTripleQuoteAt(position + 1)) {
        raw.write(reader.slice(chunk, position));
        chunk = position + 1;
        position += 4;
        continue;
      }
      final width = reader.characterWidthAt(position);
      if (width == 0) {
        return _failAt(start, position);
      }
      position += width;
    }
    raw.write(reader.slice(chunk, position));
    final value = _blockString.valueOf('$raw');
    return Token(.blockString, start, position + 3, value: value);
  }

  bool _isTripleQuoteAt(int offset) =>
      reader.unitAt(offset) == 0x22 &&
      reader.unitAt(offset + 1) == 0x22 &&
      reader.unitAt(offset + 2) == 0x22;

  /// Reports a lone surrogate, or the end when [position] is there, and
  /// returns an error token up to the closing quotes.
  Token _failAt(int start, int position) {
    if (reader.unitAt(position) < 0) {
      const message = 'Unterminated string.';
      reader.report(.unterminatedString, message, position, position);
      return Token(.error, start, position);
    }
    final character = reader.describe(position);
    reader.report(
      .invalidCharacter,
      'Invalid character within String: $character.',
      position,
      position + 1,
    );
    var end = position + 1;
    while (end < reader.length && !_isTripleQuoteAt(end)) {
      end += reader.unitAt(end) == 0x5c && _isTripleQuoteAt(end + 1) ? 4 : 1;
    }
    return Token(.error, start, end < reader.length ? end + 3 : end);
  }
}
