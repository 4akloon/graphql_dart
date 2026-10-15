import 'dart:collection';

/// A map that keeps at most [capacity] entries and drops the least recently
/// used one first (R4.8). A read counts as a use.
final class LruMap<K, V extends Object>(
  /// The most entries kept; zero keeps none.
  final int capacity,
) {
  /// Creates an empty map.
  this : assert(capacity >= 0, 'a capacity is not negative');

  // A LinkedHashMap iterates in insertion order, so the first key is the
  // least recently used one once a hit re-inserts its entry.
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  /// The number of entries held.
  int get length => _entries.length;

  /// The value stored for [key], which becomes the most recently used, or
  /// null.
  V? use(K key) {
    final value = _entries.remove(key);
    if (value != null) {
      _entries[key] = value;
    }
    return value;
  }

  /// Stores [value] for [key] as the most recently used entry and drops the
  /// least recently used one when the map is over its capacity.
  void store(K key, V value) {
    if (capacity == 0) {
      return;
    }
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Whether [key] is held; unlike [use] it does not count as a use.
  bool contains(K key) => _entries.containsKey(key);
}
