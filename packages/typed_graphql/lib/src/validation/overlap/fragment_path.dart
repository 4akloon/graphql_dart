/// The fragments expanded on the way from the top of a definition to the
/// selection being merged: a fragment on the path is not expanded again,
/// so a recursive fragment ends.
final class FragmentPath {
  /// Creates an empty path.
  FragmentPath();

  final Map<String, int> _counts = {};

  /// Whether the fragment named [name] is on the path.
  bool contains(String name) => _counts.containsKey(name);

  /// Puts [names] on the path.
  void enter(List<String> names) {
    for (final name in names) {
      _counts.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  /// Takes [names], put there by [enter], off the path.
  void leave(List<String> names) {
    for (final name in names) {
      if (_counts[name] case final count? when count > 1) {
        _counts[name] = count - 1;
      } else {
        _counts.remove(name);
      }
    }
  }
}
