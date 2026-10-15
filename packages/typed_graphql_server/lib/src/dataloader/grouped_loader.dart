import 'dart:async';

import 'batch_loader.dart';
import 'loader_queue.dart';

/// Loads the list of values that belong to a key, in batches: one parent, many
/// children.
///
/// Where a [BatchLoader] maps a key to one value, a `GroupedLoader` maps it to
/// a list, for example the posts of an author. Without it, the `posts` of 50
/// authors are 50 queries; with it, the resolvers of one level ask for their
/// author's id and one function fetches the posts of all of them, for example
/// with `WHERE author_id IN (...)`. Batching, de-duplication, the per-request
/// cache and the handling of failures are those of [BatchLoader].
///
/// The lists a loader hands out are unmodifiable copies of what the batch
/// function returned, so a resolver cannot change the value another field
/// reads from the cache.
///
/// {@category dataloader}
final class GroupedLoader<K, V> {
  /// Creates a loader that fetches keys with [load], at most `maxBatchSize`
  /// per call (no limit when null). With `cachesValues` off nothing is reused
  /// across batches.
  ///
  /// [load] gets the distinct keys of a batch in the order they were asked
  /// and returns a map; a key it leaves out has an empty list. Throws an
  /// [ArgumentError] when `maxBatchSize` is less than 1.
  GroupedLoader(
    FutureOr<Map<K, List<V>>> Function(List<K> keys) load, {
    int? maxBatchSize,
    bool cachesValues = true,
  }) : _queue = LoaderQueue<K, List<V>>(
         (keys) {
           final result = load(keys);
           return result is Future<Map<K, List<V>>>
               ? result.then(_freeze<K, V>)
               : _freeze<K, V>(result);
         },
         maxBatchSize: maxBatchSize,
         cachesValues: cachesValues,
         missing: (_) => List<V>.unmodifiable(<V>[]),
       );

  final LoaderQueue<K, List<V>> _queue;

  static Map<K, List<V>> _freeze<K, V>(Map<K, List<V>> groups) => {
    for (final entry in groups.entries)
      entry.key: List<V>.unmodifiable(entry.value),
  };

  /// The values for [key]; the cached future when there is one.
  Future<List<V>> load(K key) => _queue.load(key);

  /// The lists for [keys], in the order given; fails when any key fails.
  Future<List<List<V>>> loadMany(Iterable<K> keys) =>
      Future.wait([for (final key in keys) _queue.load(key)]);

  /// Caches a copy of [values] for [key] unless the key is already cached.
  ///
  /// Does nothing when the loader does not cache.
  void prime(K key, List<V> values) =>
      _queue.prime(key, List<V>.unmodifiable(values));

  /// Forgets the cached list of [key]; futures already handed out still
  /// complete.
  void clear(K key) => _queue.clear(key);

  /// Forgets every cached list.
  void clearAll() => _queue.clearAll();
}
