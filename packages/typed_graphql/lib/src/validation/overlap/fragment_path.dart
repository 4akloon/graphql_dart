/// The fragments expanded on the way from the top of a definition to the
/// selection being merged: a fragment on the path is not expanded again,
/// so a recursive fragment ends.
final class FragmentPath(
  /// The fragments that may be on a cycle, which [hasCyclic] looks for.
  final Set<String> cyclic,
) {
  /// Creates an empty path.
  this;

  final Map<String, int> _counts = {};
  int _cyclicCount = 0;

  /// Whether the fragment named [name] is on the path.
  bool contains(String name) => _counts.containsKey(name);

  /// Whether a fragment that may be on a cycle is on the path.
  bool get hasCyclic => _cyclicCount > 0;

  /// Puts [names] on the path.
  void enter(List<String> names) {
    for (final name in names) {
      _counts.update(name, (count) => count + 1, ifAbsent: () => 1);
      if (cyclic.contains(name)) _cyclicCount++;
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
      if (cyclic.contains(name)) _cyclicCount--;
    }
  }
}
