/// The signature of one declaration, read from its blanked text: whether
/// it is callable, its name and how many parameters it takes.
final class Signature(String text) {
  /// The parameter list of a function type, replaced by `Function` so its
  /// parentheses and commas are not read as the declaration's.
  static final RegExp _functionType = RegExp(
    r'\bFunction\s*\((?:[^()]|\([^()]*\))*\)',
  );

  /// `operator ==(`, `operator []=(`: the symbol is replaced so its `=` is
  /// not read as an assignment.
  static final RegExp _operator = RegExp(r'\boperator\s*([^\s(]+)\s*\(');

  /// The `(` of a parameter list: it follows a name or type parameters.
  static final RegExp _parameterList = RegExp(r'[\w$>]\s*\(');

  static final RegExp _accessor = RegExp(r'\b(get|set)\s+([A-Za-z_$][\w$]*)');

  static final RegExp _trailingName = RegExp(
    r'([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?)$',
  );

  /// The operator symbol, such as `==`; null when this is no operator.
  final String? _operatorSymbol = _operator.firstMatch(text)?[1];

  /// The text with function types and operator symbols replaced.
  final String _text = text
      .replaceAll(_functionType, 'Function')
      .replaceAll(_operator, 'operator x(');

  // `late`: both are derived from [_text], which a field initializer
  // cannot read.
  late final String _firstLine = _text.split('\n').first;

  /// The offset in the first line of what makes the declaration callable:
  /// the `(` of its parameters, its `=>`, or a `{` that ends the line;
  /// -1 when there is none.
  late final int _marker = _firstOf([
    _parameterList.firstMatch(_firstLine)?.end ?? 0,
    _firstLine.indexOf('=>') + 1,
    if (_firstLine.trimRight().endsWith('{')) _firstLine.lastIndexOf('{') + 1,
  ]);

  /// Whether this is a method, getter, setter, operator, constructor or
  /// function rather than a field or a variable.
  bool get isCallable {
    final assignment = _assignmentIn(_firstLine);
    return _marker >= 0 && (assignment < 0 || assignment > _marker);
  }

  /// The declared name: `run`, `Type.named`, `operator ==`, `value=` for a
  /// setter, `this` for the body of a primary constructor.
  String get name {
    final head = _firstLine.substring(0, _nameEnd);
    if (_operatorSymbol case final symbol?) {
      return 'operator $symbol';
    }
    if (RegExp(r'^\s*this\b').hasMatch(head)) {
      return 'this';
    }
    if (_accessor.firstMatch(head) case final accessor?) {
      return accessor[1] == 'set' ? '${accessor[2]}=' : accessor[2]!;
    }
    final bare = _withoutTypeParameters(head);
    return _trailingName.firstMatch(bare)?[1] ?? head.trim();
  }

  /// Where the name ends in the first line: at the marker of a callable,
  /// at the `=` or `;` of a field.
  int get _nameEnd {
    if (isCallable) {
      return _marker;
    }
    final assignment = _assignmentIn(_firstLine);
    final semicolon = _firstLine.indexOf(';');
    return assignment >= 0
        ? assignment
        : (semicolon >= 0 ? semicolon : _firstLine.length);
  }

  /// The number of parameters in the parameter list; 0 when there is
  /// none.
  int get parameterCount {
    final match = _parameterList.firstMatch(_firstLine);
    return match == null || match.end - 1 > _marker
        ? 0
        : _countItems(match.end);
  }

  /// The items of the list that starts at [from], up to its `)`. A `{`
  /// or `[` that opens a group of named or optional parameters is not a
  /// bracket; the group is always last.
  int _countItems(int from) {
    var depth = 0;
    var count = 0;
    var hasItem = false;
    for (var i = from; i < _text.length; i++) {
      final unit = _text[i];
      if (depth == 0 && ')]}'.contains(unit)) {
        break;
      }
      if (depth == 0 && unit == ',') {
        count++;
        hasItem = false;
      } else if (unit.trim().isNotEmpty && (hasItem || !'{['.contains(unit))) {
        hasItem = true;
        depth += _bracketChange(unit);
      }
    }
    return count + (hasItem ? 1 : 0);
  }

  static int _bracketChange(String unit) => switch (unit) {
    '(' || '[' || '{' || '<' => 1,
    ')' || ']' || '}' || '>' => -1,
    _ => 0,
  };

  /// The offset of the first `=` in [line] outside brackets that is an
  /// assignment (not `==`, `=>`, `<=`, `>=` or `!=`); -1 when there is
  /// none.
  static int _assignmentIn(String line) {
    var depth = 0;
    for (var i = 0; i < line.length; i++) {
      final before = i > 0 ? line[i - 1] : ' ';
      final after = i + 1 < line.length ? line[i + 1] : ' ';
      if (depth == 0 &&
          line[i] == '=' &&
          !'=!<>'.contains(before) &&
          !'=>'.contains(after)) {
        return i;
      }
      depth += _bracketChange(line[i]);
    }
    return -1;
  }

  /// The smallest of [offsets] above 0, minus one; -1 when none is.
  static int _firstOf(List<int> offsets) {
    final found = [
      for (final offset in offsets)
        if (offset > 0) offset,
    ];
    return found.isEmpty ? -1 : found.reduce((a, b) => a < b ? a : b) - 1;
  }

  /// [text] trimmed, without a trailing `<...>`.
  static String _withoutTypeParameters(String text) {
    final trimmed = text.trimRight();
    var depth = 0;
    for (var i = trimmed.length - 1; i >= 0 && trimmed.endsWith('>'); i--) {
      depth += switch (trimmed[i]) {
        '>' => 1,
        '<' => -1,
        _ => 0,
      };
      if (depth == 0) {
        return trimmed.substring(0, i).trimRight();
      }
    }
    return trimmed;
  }
}
