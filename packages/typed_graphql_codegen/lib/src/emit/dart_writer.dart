import 'doc_comment_escaper.dart';

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
    // A comment is a unit: an unclosed fence must not leak into the next one.
    _isInFence = false;
    for (final String content in text.split('\n')) {
      line(_docLine(content.trimRight()));
    }
  }

  String _docLine(String content) {
    final String trimmed = content.trim();
    if (!_isInFence && !trimmed.startsWith('```')) {
      // Descriptions come from the schema; see [DocCommentEscaper].
      return _docText(const DocCommentEscaper().escape(content));
    }
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
    return _docText(content);
  }

  String _docText(String content) => content.isEmpty ? '///' : '/// $content';

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

  /// Whether [text] written as one line at the current indentation stays
  /// within 80 columns.
  bool fits(String text) => _indentation.length + text.length <= _maxColumns;

  /// Writes `head = expression;`, breaking after the `=` when it is too long.
  void assign(String head, String expression) =>
      _continued(head, '=', expression);

  /// Writes `head => expression;`, breaking after the `=>` when it is too
  /// long.
  void arrow(String head, String expression) =>
      _continued(head, '=>', expression);

  /// Writes `head => a op b op c;` on one line when it fits, otherwise
  /// `head =>` and one operand per line, each but the last ending with
  /// [operator].
  void arrowJoined(String head, List<String> operands, String operator) {
    final String single = '$head => ${operands.join(' $operator ')};';
    if (fits(single)) {
      line(single);
      return;
    }
    line('$head =>');
    indented(() {
      indented(() {
        for (final (int index, String operand) in operands.indexed) {
          final bool isLast = index == operands.length - 1;
          line(isLast ? '$operand;' : '$operand $operator');
        }
      });
    });
  }

  void _continued(String head, String operator, String expression) {
    final String single = '$head $operator $expression;';
    if (fits(single)) {
      line(single);
      return;
    }
    if (_fitsAfterBreak(expression) ||
        !expression.endsWith(')') ||
        !expression.contains('(')) {
      line('$head $operator');
      indented(() => indented(() => line('$expression;')));
      return;
    }
    final int open = expression.indexOf('(');
    final String opening = expression.substring(0, open + 1);
    final String inner = expression.substring(open + 1, expression.length - 1);
    if (fits('$head $operator $opening')) {
      line('$head $operator $opening');
      indented(() => _breakCall(inner));
      line(');');
      return;
    }
    line('$head $operator');
    indented(() {
      indented(() {
        line(opening);
        indented(() => _breakCall(inner));
        line(');');
      });
    });
  }

  bool _fitsAfterBreak(String expression) {
    _level += 2;
    final bool result = fits('$expression;');
    _level -= 2;
    return result;
  }

  // Writes the argument [text] of a call, breaking nested single-argument
  // calls until each line fits.
  void _breakCall(String text) {
    final int open = text.indexOf('(');
    // A call without arguments cannot be broken: `(` and `)` stay together.
    if (fits('$text,') ||
        open < 0 ||
        !text.endsWith(')') ||
        open + 1 == text.length - 1) {
      line('$text,');
      return;
    }
    line(text.substring(0, open + 1));
    indented(() => _breakCall(text.substring(open + 1, text.length - 1)));
    line('),');
  }

  /// Everything written; ends with exactly one line break.
  String get text {
    final String written = _buffer.toString().trimRight();
    return written.isEmpty ? '' : '$written\n';
  }
}
