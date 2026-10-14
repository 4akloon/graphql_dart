import 'character_class.dart';
import 'source_reader.dart';

/// Reads one escape sequence of a quoted string (spec §2.9.4,
/// `EscapedCharacter` and `EscapedUnicode`).
final class EscapeReader {
  /// Creates a reader of the text of [reader].
  EscapeReader(this.reader);

  /// The text.
  final SourceReader reader;

  static const CharacterClass _classes = CharacterClass();
  static const int _backslash = 0x5c;
  static const int _u = 0x75;

  /// The escape at [position], a backslash: its decoded `value` and the
  /// code units it spans; `value` is null when it is invalid, and `size`
  /// then covers the text graphql-js quotes in its message.
  ({String? value, int size}) read(int position) {
    if (reader.unitAt(position + 1) != _u) {
      return (value: _character(reader.unitAt(position + 1)), size: 2);
    }
    return reader.unitAt(position + 2) == 0x7b
        ? _variableWidth(position)
        : _fixedWidth(position);
  }

  String? _character(int unit) => switch (unit) {
    0x22 => '"',
    0x5c => r'\',
    0x2f => '/',
    0x62 => '\b',
    0x66 => '\f',
    0x6e => '\n',
    0x72 => '\r',
    0x74 => '\t',
    _ => null,
  };

  /// `\u{...}`: at most eight digits, a scalar value. The loop and the
  /// overflow test mirror graphql-js so messages quote the same text.
  ({String? value, int size}) _variableWidth(int position) {
    var point = 0;
    var size = 3;
    while (size < 12) {
      final unit = reader.unitAt(position + size);
      size++;
      if (unit == 0x7d) {
        return size < 5 || !_classes.isScalarValue(point)
            ? (value: null, size: size)
            : (value: String.fromCharCode(point), size: size);
      }
      final digit = _classes.hexValue(unit);
      point = point * 16 + digit;
      if (digit < 0 || point >= 0x80000000) {
        break;
      }
    }
    return (value: null, size: size);
  }

  /// `\uXXXX`, where a leading surrogate must be followed by an escaped
  /// trailing one.
  ({String? value, int size}) _fixedWidth(int position) {
    final code = _hex4(position + 2);
    if (_classes.isScalarValue(code)) {
      return (value: String.fromCharCode(code), size: 6);
    }
    final hasPair =
        _classes.isLeadingSurrogate(code) &&
        reader.unitAt(position + 6) == _backslash &&
        reader.unitAt(position + 7) == _u &&
        _classes.isTrailingSurrogate(_hex4(position + 8));
    return hasPair
        ? (value: String.fromCharCodes([code, _hex4(position + 8)]), size: 12)
        : (value: null, size: 6);
  }

  /// The four hexadecimal digits at [offset], or -1 when one is not.
  int _hex4(int offset) {
    var code = 0;
    for (var i = 0; i < 4; i++) {
      final digit = _classes.hexValue(reader.unitAt(offset + i));
      if (digit < 0) {
        return -1;
      }
      code = code * 16 + digit;
    }
    return code;
  }
}
