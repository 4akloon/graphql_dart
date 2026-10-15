import 'dart:async';

import 'loader_queue.dart';
import 'missing_value_exception.dart';

/// Loads values by key in batches, so that N resolvers asking for one value
/// each cause one call to a function that fetches many.
///
/// Without it, a list of 100 users that each load their company is 100
/// queries (the N+1 problem). The first [load] of a batch schedules its
/// dispatch for when the microtask queue has drained, so every resolver of one
/// level, also one that `await`s a completed future before it calls [load],
/// joins the same call. A key asked twice in a batch is sent once.
///
/// A loader belongs to one request: create it in the code that makes the
/// request's context, so its cache and its batches never cross requests. With
/// `cachesValues` (the default) a loaded, pending or primed value is reused
/// for the loader's lifetime; call [clear] or [clearAll] after a mutation. A
/// failed batch is not cached: every key of it fails with the error and is
/// loaded again by the next [load].
///
/// {@category dataloader}
final class BatchLoader<K, V> {
  /// Creates a loader that fetches keys with [load], at most `maxBatchSize`
  /// per call (no limit when null).
  ///
  /// [load] gets the distinct keys of a batch in the order they were asked
  /// and returns a map; a key it leaves out completes with `null` when [V] is
  /// nullable and fails with [MissingValueException] otherwise. Throws an
  /// [ArgumentError] when `maxBatchSize` is less than 1.
  BatchLoader(
    FutureOr<Map<K, V>> Function(List<K> keys) load, {
    int? maxBatchSize,
    bool cachesValues = true,
  }) : _queue = LoaderQueue<K, V>(
         load,
         maxBatchSize: maxBatchSize,
         cachesValues: cachesValues,
         missing: (key) {
           if (null is V) {
             return null as V;
           }
           throw MissingValueException(key);
         },
       );

  final LoaderQueue<K, V> _queue;

  /// The value for [key]; the cached future when there is one.
  Future<V> load(K key) => _queue.load(key);

  /// The values for [keys], in the order given; fails when any key fails.
  Future<List<V>> loadMany(Iterable<K> keys) =>
      Future.wait([for (final key in keys) _queue.load(key)]);

  /// Caches [value] for [key] unless the key is already cached.
  ///
  /// Does nothing when the loader does not cache.
  void prime(K key, V value) => _queue.prime(key, value);

  /// Forgets the cached value of [key]; futures already handed out still
  /// complete.
  void clear(K key) => _queue.clear(key);

  /// Forgets every cached value.
  void clearAll() => _queue.clearAll();
}
