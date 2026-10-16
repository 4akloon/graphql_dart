import 'package:meta/meta.dart';

/// Finds a byte sequence in a stream of bytes fed one at a time, in linear
/// time (Knuth-Morris-Pratt), without keeping what it has seen.
@internal
final class SequenceMatcher {
  /// Creates a matcher for [pattern], which is not empty.
  SequenceMatcher(List<int> pattern)
    : _pattern = List.unmodifiable(pattern),
      _fallback = _fallbackOf(pattern);

  final List<int> _pattern;
  final List<int> _fallback;
  int _matched = 0;

  /// Reads [byte] and tells whether it completes the pattern; the next match
  /// is searched from the byte after.
  bool feed(int byte) {
    while (_matched > 0 && byte != _pattern[_matched]) {
      _matched = _fallback[_matched - 1];
    }
    if (byte == _pattern[_matched]) _matched++;
    if (_matched < _pattern.length) return false;
    _matched = 0;
    return true;
  }

  /// Forgets the bytes read so far.
  void reset() => _matched = 0;

  static List<int> _fallbackOf(List<int> pattern) {
    final fallback = List<int>.filled(pattern.length, 0);
    var length = 0;
    for (var index = 1; index < pattern.length; index++) {
      while (length > 0 && pattern[index] != pattern[length]) {
        length = fallback[length - 1];
      }
      if (pattern[index] == pattern[length]) length++;
      fallback[index] = length;
    }
    return fallback;
  }
}
