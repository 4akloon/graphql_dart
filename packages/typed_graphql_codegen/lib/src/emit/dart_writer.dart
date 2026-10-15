/// A text builder for generated Dart code.
///
/// {@category codegen}
final class DartWriter {
  /// Creates an empty writer at indentation level zero.
  DartWriter();

  static const int _maxColumns = 80;

  final StringBuffer _buffer = StringBuffer();
  int _level = 0;
  bool _isInFence = false;

  String get _indentation => '  ' * _level;

  /// Writes [text] as one line at the current indentation.
  ///
  /// An empty line has no trailing spaces.
  void line([String text = '']) {
    if (text.isEmpty) {
      _buffer.writeln();
    } else {
      _buffer.writeln('$_indentation$text');
    }
  }

  /// Runs [body] one indentation level deeper.
  void indented(void Function() body) {
    _level++;
    try {
      body();
    } finally {
      _level--;
    }
  }

  /// Writes `header {`, the [body] one level deeper, and `}`.
  void block(String header, void Function() body) {
    line('$header {');
    indented(body);
    line('}');
  }

  /// Writes [text] as a `///` comment, one comment line per line of [text].
  ///
  /// A bare Markdown fence that opens a block gets the language `text`.
  void doc(String text) {
    for (final String content in text.split('\n')) {
      line(_docLine(content));
    }
  }

  String _docLine(String content) {
    final String trimmed = content.trim();
    if (trimmed.startsWith('```')) {
      if (_isInFence) {
        _isInFence = false;
      } else {
        _isInFence = true;
        if (trimmed == '```') {
          return '/// ```text';
        }
      }
    }
    return content.isEmpty ? '///' : '/// $content';
  }

  /// Writes `open + items.join(', ') + close` on one line when it fits in 80
  /// columns, otherwise one item per line, each ending with `,`.
  void items(String open, List<String> items, String close) {
    final String single = '$open${items.join(', ')}$close';
    if (_indentation.length + single.length <= _maxColumns) {
      line(single);
      return;
    }
    line(open);
    indented(() {
      for (final String item in items) {
        line('$item,');
      }
    });
    line(close);
  }

  /// Everything written; ends with exactly one line break.
  String get text {
    final String written = _buffer.toString().trimRight();
    return written.isEmpty ? '' : '$written\n';
  }
}
