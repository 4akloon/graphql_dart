import 'blanked_code.dart';

/// Measures how deeply control blocks nest: the `{` of `if`, `else`,
/// `for`, `while`, `do`, `switch` (statement or expression), `try`,
/// `catch`, `on` and `finally`.
///
/// Other braces (bodies, closures, collection literals, patterns) do not
/// count, but a control block inside a closure counts on top of the
/// blocks around the closure.
final class NestingMeter(final BlankedCode code) {
  static final RegExp _controlHead = RegExp(
    r'^(?:if|else|for|await\s+for|while|do|switch|try|catch|on|finally)\b',
  );

  static final RegExp _switchHead = RegExp(r'\bswitch\s*\(');

  /// The index of every line where a control block opens deeper than
  /// [limit], in file order.
  List<int> linesDeeperThan(int limit) {
    final found = <int>[];
    final frames = [_Frame(isControl: false)];
    for (final (line, unit) in code.unitsFrom(0)) {
      final frame = frames.last;
      if (unit == '{') {
        frames.add(_Frame(isControl: _isControl(frame)));
        frame.endStatement();
        if (frames.where((frame) => frame.isControl).length > limit) {
          found.add(line);
        }
      } else if (unit == '}' && frames.length > 1) {
        frames.removeLast();
        frames.last.endStatement();
      } else {
        frame.read(unit);
      }
    }
    return {...found}.toList();
  }

  /// Whether the `{` read next in [frame] opens a control block.
  bool _isControl(_Frame frame) {
    final head = frame.statement.trim();
    if (frame.parentheses == 0 && _controlHead.hasMatch(head)) {
      return true;
    }
    final switchAt = head.lastIndexOf(_switchHead);
    return switchAt >= 0 &&
        head.endsWith(')') &&
        BlankedCode.bracketBalance(head.substring(switchAt)) == 0;
  }
}

/// The statement being read inside one `{`, and how many `(` and `[` it
/// has open.
final class _Frame({required final bool isControl}) {
  final StringBuffer _statement = StringBuffer();

  int parentheses = 0;

  String get statement => _statement.toString();

  /// Adds [unit] to the statement; a `;` outside brackets ends it.
  void read(String unit) {
    parentheses += switch (unit) {
      '(' || '[' => 1,
      ')' || ']' => -1,
      _ => 0,
    };
    if (unit == ';' && parentheses == 0) {
      _statement.clear();
    } else {
      _statement.write(unit);
    }
  }

  /// Starts a new statement after a block, unless the block was inside
  /// brackets (a closure argument, a map pattern).
  void endStatement() {
    if (parentheses == 0) {
      _statement.clear();
    }
  }
}
