/// graphql-js's `LexicalDistance`: the Damerau-Levenshtein distance of an
/// option from one input, ignoring case, used to suggest names.
///
/// A case change alone counts as one edit. The rows are reused between
/// options, and an option whose distance exceeds the threshold is dropped
/// as soon as a whole row exceeds it, so a long input against short
/// options costs little.
final class LexicalDistance {
  /// Prepares to measure options against [input].
  LexicalDistance(this.input)
    : _inputLowerCase = input.toLowerCase(),
      _rows = List.generate(3, (_) => List.filled(input.length + 1, 0));

  /// The text the options are compared with.
  final String input;

  final String _inputLowerCase;
  final List<List<int>> _rows;

  /// The distance of [option] from [input]; null when it exceeds
  /// [threshold].
  int? measure(String option, int threshold) {
    if (input == option) {
      return 0;
    }
    final optionLowerCase = option.toLowerCase();
    if (_inputLowerCase == optionLowerCase) {
      return 1;
    }
    final (a, b) = optionLowerCase.length < _inputLowerCase.length
        ? (_inputLowerCase, optionLowerCase)
        : (optionLowerCase, _inputLowerCase);
    if (a.length - b.length > threshold) {
      return null;
    }
    if (!_fill(a, b, threshold)) {
      return null;
    }
    final distance = _rows[a.length % 3][b.length];
    return distance <= threshold ? distance : null;
  }

  // Fills the rows for [a] against [b], the shorter of the two, which is
  // never longer than the input, so the rows fit; false as soon as a row's
  // smallest cell exceeds [threshold].
  bool _fill(String a, String b, int threshold) {
    final rows = _rows;
    for (var j = 0; j <= b.length; j++) {
      rows[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      final current = rows[i % 3];
      var smallest = current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        current[j] = _cell(a, b, i, j, rows);
        if (current[j] < smallest) {
          smallest = current[j];
        }
      }
      if (smallest > threshold) {
        return false;
      }
    }
    return true;
  }

  static int _cell(String a, String b, int i, int j, List<List<int>> rows) {
    final up = rows[(i - 1) % 3];
    final current = rows[i % 3];
    final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
    var cell = _min(up[j] + 1, current[j - 1] + 1, up[j - 1] + cost);
    if (i > 1 &&
        j > 1 &&
        a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
        a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
      final transposed = rows[(i - 2) % 3][j - 2] + 1;
      if (transposed < cell) {
        cell = transposed;
      }
    }
    return cell;
  }

  static int _min(int a, int b, int c) {
    final ab = a < b ? a : b;
    return ab < c ? ab : c;
  }
}
