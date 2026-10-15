import 'lexical_distance.dart';

/// graphql-js's "Did you mean" text: `suggestionList`, `didYouMean`,
/// `orList` and `naturalCompare`, shared by the messages that suggest a
/// name.
///
/// {@category diagnostics}
final class const Suggestions() {
  /// Creates the helper; it keeps no state.
  this;

  /// The most names [didYouMean] lists.
  static const int maxSuggestions = 5;

  /// The longest input [listFor] looks for suggestions of, in UTF-16 code
  /// units; a longer one has none. graphql-js has no such limit, but a name
  /// that long is not a typo of a name of a schema, and measuring it would
  /// let a hostile document make every error cost its length.
  static const int maxInputLength = 256;

  static final RegExp _digit = RegExp('[0-9]');

  /// The [options] close to [input], closest first and then in natural
  /// order (graphql-js's `suggestionList`); none for an input longer than
  /// [maxInputLength].
  List<String> listFor(String input, Iterable<String> options) {
    if (input.length > maxInputLength) {
      return const [];
    }
    final distance = LexicalDistance(input);
    final threshold = (input.length * 0.4).floor() + 1;
    final distances = <String, int>{
      for (final option in options)
        option: ?distance.measure(option, threshold),
    };
    final sorted = distances.entries.toList()
      ..sort((a, b) {
        final difference = a.value - b.value;
        return difference != 0 ? difference : naturalCompare(a.key, b.key);
      });
    return [for (final entry in sorted) entry.key];
  }

  /// ` Did you mean "A", "B", or "C"?`, naming at most [maxSuggestions]
  /// of [suggestions] after [subject] when given; empty for no suggestion.
  String didYouMean(List<String> suggestions, {String? subject}) {
    if (suggestions.isEmpty) {
      return '';
    }
    final quoted = [
      for (final suggestion in suggestions.take(maxSuggestions))
        '"$suggestion"',
    ];
    return ' Did you mean ${subject == null ? '' : '$subject '}'
        '${orList(quoted)}?';
  }

  /// `A`, `A or B`, `A, B, or C` (graphql-js's `orList`).
  String orList(List<String> items) => switch (items) {
    [] => '',
    [final only] => only,
    [final first, final second] => '$first or $second',
    [...final rest, final last] => '${rest.join(', ')}, or $last',
  };

  /// Compares [a] and [b] with runs of digits as numbers, as graphql-js's
  /// `naturalCompare` does: negative, zero or positive.
  ///
  /// A run that starts with `0` is that zero alone. Runs compare by length
  /// and then by text, which is their numeric order without parsing them,
  /// so a run of any length compares the same on every platform.
  int naturalCompare(String a, String b) {
    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      if (_isDigit(a, i) && _isDigit(b, j)) {
        final aEnd = _runEnd(a, i);
        final bEnd = _runEnd(b, j);
        final order = _compareRuns(a.substring(i, aEnd), b.substring(j, bEnd));
        if (order != 0) {
          return order;
        }
        (i, j) = (aEnd, bEnd);
      } else {
        final order = a.codeUnitAt(i).compareTo(b.codeUnitAt(j));
        if (order != 0) {
          return order;
        }
        (i, j) = (i + 1, j + 1);
      }
    }
    return (a.length - b.length).sign;
  }

  static bool _isDigit(String text, int index) =>
      _digit.matchAsPrefix(text, index) != null;

  static int _runEnd(String text, int start) {
    if (text.codeUnitAt(start) == 0x30) {
      return start + 1;
    }
    var end = start + 1;
    while (end < text.length && _isDigit(text, end)) {
      end++;
    }
    return end;
  }

  static int _compareRuns(String a, String b) =>
      a.length != b.length ? a.length.compareTo(b.length) : a.compareTo(b);
}
