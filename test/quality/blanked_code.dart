/// The text of a Dart library with every comment and the contents of
/// every string replaced by spaces, so that the rules can read the code
/// with regular expressions and count brackets.
///
/// Line breaks and the quotes of strings stay, so a line number and a
/// column of the blanked text are those of the source. An interpolation
/// (`${...}`) is part of its string and is blanked with it.
final class BlankedCode {
  /// Blanks [source].
  BlankedCode(String source) : lines = _Blanker(source).blank().split('\n');

  /// The blanked lines, in order.
  final List<String> lines;

  // `late`: most files are read by rules that never look at brackets.
  /// How many `(`, `[` and `{` are open at the start of each line.
  late final List<int> depths = _depths();

  List<int> _depths() {
    final result = <int>[];
    var depth = 0;
    for (final line in lines) {
      result.add(depth);
      depth += bracketBalance(line);
    }
    return result;
  }

  /// Every code unit from line [from] on, with the index of its line; a
  /// `\n` ends every line.
  Iterable<(int, String)> unitsFrom(int from) sync* {
    for (var line = from; line < lines.length; line++) {
      for (final unit in '${lines[line]}\n'.split('')) {
        yield (line, unit);
      }
    }
  }

  /// The number of `(`, `[` and `{` in [text] minus the number of `)`,
  /// `]` and `}`.
  static int bracketBalance(String text) {
    var balance = 0;
    for (var i = 0; i < text.length; i++) {
      balance += switch (text[i]) {
        '(' || '[' || '{' => 1,
        ')' || ']' || '}' => -1,
        _ => 0,
      };
    }
    return balance;
  }
}

/// The state machine behind [BlankedCode]: code, comments, strings and
/// the interpolations inside strings.
final class _Blanker(final String source) {
  final StringBuffer _out = StringBuffer();

  /// For every string being read, innermost last: its quote (`'`, `"`,
  /// `'''` or `"""`), and whether it is raw.
  final List<({String quote, bool isRaw})> _strings = [];

  /// For every interpolation being read, innermost last: how many `{` it
  /// has open.
  final List<int> _interpolations = [];

  int _at = 0;

  /// [source] with comments and string contents blanked.
  String blank() {
    while (_at < source.length) {
      if (_strings.length > _interpolations.length) {
        _readString();
      } else {
        _readCode();
      }
    }
    return _out.toString();
  }

  void _readCode() {
    if (source.startsWith('//', _at)) {
      _skipWhile((unit) => unit != '\n');
    } else if (source.startsWith('/*', _at)) {
      _skipBlockComment();
    } else if (_quoteAt(_at) case final quote?) {
      final isRaw = _at > 0 && source[_at - 1] == 'r' && !_isNamePart(_at - 2);
      _strings.add((quote: quote, isRaw: isRaw));
      _keep(quote.length);
    } else {
      _readCodeUnit();
    }
  }

  void _readCodeUnit() {
    final unit = source[_at];
    if (_interpolations.isNotEmpty && unit == '{') {
      _interpolations.last++;
    } else if (_interpolations.isNotEmpty && unit == '}') {
      if (_interpolations.last == 0) {
        _interpolations.removeLast();
        _blank(1);
        return;
      }
      _interpolations.last--;
    }
    _keep(1);
  }

  void _readString() {
    final (:quote, :isRaw) = _strings.last;
    if (source.startsWith(quote, _at)) {
      _strings.removeLast();
      _keep(quote.length);
    } else if (!isRaw && source[_at] == r'\') {
      _blank(2);
    } else if (!isRaw && source.startsWith(r'${', _at)) {
      _interpolations.add(0);
      _blank(2);
    } else {
      _blank(1);
    }
  }

  /// The quote that opens a string at [offset], or null.
  String? _quoteAt(int offset) {
    for (final quote in const ["'''", '"""', "'", '"']) {
      if (source.startsWith(quote, offset)) {
        return quote;
      }
    }
    return null;
  }

  bool _isNamePart(int offset) =>
      offset >= 0 && RegExp(r'[\w$]').hasMatch(source[offset]);

  void _skipBlockComment() {
    var depth = 0;
    do {
      if (source.startsWith('/*', _at)) {
        depth++;
        _blank(2);
      } else if (source.startsWith('*/', _at)) {
        depth--;
        _blank(2);
      } else {
        _blank(1);
      }
    } while (depth > 0 && _at < source.length);
  }

  void _skipWhile(bool Function(String unit) test) {
    while (_at < source.length && test(source[_at])) {
      _blank(1);
    }
  }

  /// Copies [count] code units, or blanks them inside an interpolation.
  void _keep(int count) {
    final end = (_at + count).clamp(0, source.length);
    if (_interpolations.isEmpty) {
      _out.write(source.substring(_at, end));
    } else {
      _blankRange(end);
    }
    _at = end;
  }

  void _blank(int count) {
    _blankRange((_at + count).clamp(0, source.length));
  }

  void _blankRange(int end) {
    for (; _at < end; _at++) {
      _out.write(source[_at] == '\n' ? '\n' : ' ');
    }
  }
}
