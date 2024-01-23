import 'ignored_char.dart';

class IgnoredChars {
  final List<IgnoredChar> left;
  final List<IgnoredChar> right;

  IgnoredChars({
    List<IgnoredChar> left = const [],
    List<IgnoredChar> right = const [],
  })  : left = List.unmodifiable(left),
        right = List.unmodifiable(right);

  static IgnoredChars empty() => IgnoredChars();
}
