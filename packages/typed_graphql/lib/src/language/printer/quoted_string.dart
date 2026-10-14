/// A string value as a quoted GraphQL string, escaped as graphql-js's
/// `printString` does: control characters, `"`, `\` and U+007F–U+009F.
final class QuotedString {
  /// Creates the printer; it keeps no state.
  const QuotedString();

  /// [value] between double quotes, escaped.
  String print(String value) {
    final buffer = StringBuffer('"');
    for (final unit in value.codeUnits) {
      final escape = _escape(unit);
      if (escape == null) {
        buffer.writeCharCode(unit);
      } else {
        buffer.write(escape);
      }
    }
    buffer.write('"');
    return buffer.toString();
  }

  static String? _escape(int unit) => switch (unit) {
    0x08 => r'\b',
    0x09 => r'\t',
    0x0a => r'\n',
    0x0c => r'\f',
    0x0d => r'\r',
    0x22 => r'\"',
    0x5c => r'\\',
    < 0x20 || (>= 0x7f && <= 0x9f) =>
      '\\u${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}',
    _ => null,
  };
}
