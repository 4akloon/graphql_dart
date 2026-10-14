/// Finds the items of a list by name, building its index on the first
/// lookup: element classes use it to answer `argumentNamed` in constant
/// time, so a rule that looks up every argument of a large field does not
/// scan the list for each.
final class NamedLookup<T extends Object>(
  /// The items; the list must not change.
  final List<T> items,

  /// The name of an item.
  final String Function(T item) nameOf,
) {
  /// Creates a lookup over [items].
  this;

  // Only for lookups, never iterated. Built from the end, so the first of
  // two items with one name wins, as a scan would find it.
  late final Map<String, T> _byName = {
    for (final item in items.reversed) nameOf(item): item,
  };

  /// The item named [name]; null when there is none.
  T? named(String name) => _byName[name];
}
