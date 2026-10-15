/// Writes a Dart string literal that satisfies `prefer_single_quotes` and
/// `use_raw_strings`.
///
/// {@category codegen}
final class DartStringLiteral {
  /// Creates the writer.
  const DartStringLiteral();

  /// The Dart literal for [value].
  String of(String value) {
    final bool isPlain = !_hasControlOrSurrogate(value);
    final bool needsRaw = value.contains(r'\') || value.contains(r'$');
    if (isPlain && !value.contains("'")) {
      return needsRaw ? "r'$value'" : "'$value'";
    }
    if (isPlain && !value.contains('"')) {
      return needsRaw ? 'r"$value"' : '"$value"';
    }
    return _escaped(value);
  }

  bool _hasControlOrSurrogate(String value) {
    final List<int> units = value.codeUnits;
    for (int index = 0; index < units.length; index++) {
      final int unit = units[index];
      if (unit < 0x20 || unit == 0x7f) {
        return true;
      }
      if (_isHighSurrogate(unit) &&
          index + 1 < units.length &&
          _isLowSurrogate(units[index + 1])) {
        index++;
      } else if (_isHighSurrogate(unit) || _isLowSurrogate(unit)) {
        return true;
      }
    }
    return false;
  }

  bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  String _escaped(String value) {
    final StringBuffer out = StringBuffer("'");
    final List<int> units = value.codeUnits;
    for (int index = 0; index < units.length; index++) {
      final int unit = units[index];
      if (_isHighSurrogate(unit) &&
          index + 1 < units.length &&
          _isLowSurrogate(units[index + 1])) {
        out.write(String.fromCharCodes(<int>[unit, units[index + 1]]));
        index++;
      } else {
        out.write(_escapedUnit(unit));
      }
    }
    out.write("'");
    return out.toString();
  }

  String _escapedUnit(int unit) {
    return switch (unit) {
      0x5c => r'\\',
      0x27 => r"\'",
      0x24 => r'\$',
      0x0a => r'\n',
      0x0d => r'\r',
      0x09 => r'\t',
      _ when unit < 0x20 || unit == 0x7f || _isSurrogate(unit) =>
        '\\u{${unit.toRadixString(16).toUpperCase()}}',
      _ => String.fromCharCode(unit),
    };
  }

  bool _isSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDFFF;
}
