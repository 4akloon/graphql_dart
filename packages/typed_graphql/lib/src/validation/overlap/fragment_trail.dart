/// The fragments spread between a selection set and a field it selects,
/// innermost first: a shared list, so a chain of fragments 100000 deep
/// costs one link per fragment.
final class FragmentTrail {
  const FragmentTrail._root() : name = null, outer = null, length = 0;

  FragmentTrail._(String this.name, FragmentTrail this.outer)
    : length = outer.length + 1;

  /// No fragment: a field written in the selection set itself.
  static const FragmentTrail empty = FragmentTrail._root();

  /// The innermost fragment; null for [empty].
  final String? name;

  /// The trail without [name]; null for [empty].
  final FragmentTrail? outer;

  /// The number of fragments.
  final int length;

  /// This trail followed by the fragment named [fragment].
  FragmentTrail inside(String fragment) => FragmentTrail._(fragment, this);

  /// The innermost fragment that [first] and [second] both pass through,
  /// from the same spread; null when they share none.
  static String? innermostShared(FragmentTrail first, FragmentTrail second) {
    var (one, other) = (first, second);
    // Trails from one collection share their links, and every trail ends
    // in [empty], so the walk meets.
    while (!identical(one, other)) {
      if (one.length >= other.length) {
        one = one.outer ?? one;
      } else {
        other = other.outer ?? other;
      }
    }
    return one.name;
  }
}
