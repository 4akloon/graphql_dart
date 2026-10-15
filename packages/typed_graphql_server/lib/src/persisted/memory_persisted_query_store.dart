import 'dart:collection';

import 'persisted_query_store.dart';

/// A [PersistedQueryStore] in memory: the [capacity] most recently used
/// texts, the least recently used one evicted first.
///
/// The capacity bounds the memory a client can fill by registering
/// queries; each text is bounded by the server's `maxDocumentLength`.
///
/// {@category persisted}
final class MemoryPersistedQueryStore implements PersistedQueryStore {
  /// Creates a store of at most [capacity] texts; a capacity below 1 is an
  /// [ArgumentError].
  MemoryPersistedQueryStore({this.capacity = 1000}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be at least 1');
    }
  }

  /// The most texts the store holds.
  final int capacity;

  // A linked map keeps insertion order: the first key is the oldest.
  final LinkedHashMap<String, String> _texts = LinkedHashMap<String, String>();

  /// The number of texts held.
  int get length => _texts.length;

  /// The text stored for [hash], which becomes the most recently used, or
  /// null.
  @override
  String? read(String hash) {
    final text = _texts.remove(hash);
    if (text != null) _texts[hash] = text;
    return text;
  }

  /// Stores [text] for [hash] as the most recently used, evicting the least
  /// recently used text past the capacity.
  @override
  void write(String hash, String text) {
    _texts.remove(hash);
    _texts[hash] = text;
    if (_texts.length > capacity) {
      _texts.remove(_texts.keys.first);
    }
  }
}
