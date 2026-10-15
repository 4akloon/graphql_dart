import 'condition.dart';

/// A named fragment selected at one level of a selection.
final class FragmentUse(
  /// The fragment's name.
  final String fragmentName,

  /// The spread is selected when all conditions of any one list hold; one
  /// empty list means it is unconditional.
  List<List<Condition>> whenAny,
) {
  /// Creates a use.
  this;

  /// The alternatives, in first-occurrence order.
  final List<List<Condition>> whenAny = List.unmodifiable([
    for (final conditions in whenAny) List<Condition>.unmodifiable(conditions),
  ]);

  /// Whether the fragment is selected only when some variable says so.
  bool get isConditional =>
      whenAny.every((conditions) => conditions.isNotEmpty);

  /// This use merged with another spread of the same fragment under
  /// [conditions]: unconditional if either is, otherwise both alternatives
  /// with duplicates removed.
  FragmentUse merge(List<Condition> conditions) {
    if (whenAny.any((existing) => existing.isEmpty)) {
      return this;
    }
    if (conditions.isEmpty) {
      return FragmentUse(fragmentName, [const <Condition>[]]);
    }
    if (whenAny.any((existing) => _same(existing, conditions))) {
      return this;
    }
    return FragmentUse(fragmentName, [...whenAny, conditions]);
  }

  static bool _same(List<Condition> a, List<Condition> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}
