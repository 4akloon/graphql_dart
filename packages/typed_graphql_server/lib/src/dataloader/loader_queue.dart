import 'dart:async';

import 'package:meta/meta.dart';

/// The batching and caching shared by the public loaders: it collects the keys
/// of one batch, dispatches them after the microtask queue has drained and
/// completes one future per distinct key.
///
/// The timer, not a microtask, is the dispatch point so that resolvers that
/// `await` already completed futures before they call `load` still land in
/// the same batch (spec M6 section 15 item 5).
@internal
final class LoaderQueue<K, R> {
  /// Creates a queue that sends keys to [_batch], at most [maxBatchSize] per
  /// call, and asks [missing] for the result of a key the call left out.
  LoaderQueue(
    this._batch, {
    required this.missing,
    this.maxBatchSize,
    this.cachesValues = true,
  }) {
    final size = maxBatchSize;
    if (size != null && size < 1) {
      throw ArgumentError.value(size, 'maxBatchSize', 'must be at least 1');
    }
  }

  final FutureOr<Map<K, R>> Function(List<K> keys) _batch;

  /// The result of a key the batch function left out; it may throw.
  final R Function(K key) missing;

  /// The most keys one call of the batch function gets, null for no limit.
  final int? maxBatchSize;

  /// Whether a loaded, pending or primed value is reused.
  final bool cachesValues;

  // Dart's default map keeps insertion order, which is the call order.
  Map<K, Completer<R>> _pending = {};
  final Map<K, Future<R>> _cache = {};

  /// The result for [key]: the cached future, or one that completes when the
  /// batch it joins is dispatched.
  Future<R> load(K key) {
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    final queued = _pending[key];
    if (queued != null) {
      return queued.future;
    }
    if (_pending.isEmpty) {
      Timer.run(_dispatch);
    }
    final completer = Completer<R>();
    _pending[key] = completer;
    final future = completer.future;
    if (cachesValues) {
      _cache[key] = future;
      // A failure is not cached, and this listener also keeps the future from
      // being an uncaught error when no caller listens.
      future.then<void>((_) {}, onError: (Object _) => _evict(key, future));
    }
    return future;
  }

  /// Caches [value] for [key] unless the key is already cached.
  void prime(K key, R value) {
    if (cachesValues && !_cache.containsKey(key)) {
      _cache[key] = Future<R>.value(value);
    }
  }

  /// Forgets the cached result of [key].
  void clear(K key) => _cache.remove(key);

  /// Forgets every cached result.
  void clearAll() => _cache.clear();

  void _evict(K key, Future<R> future) {
    if (identical(_cache[key], future)) {
      _cache.remove(key);
    }
  }

  void _dispatch() {
    final batch = _pending;
    _pending = {};
    final keys = batch.keys.toList();
    final size = maxBatchSize ?? keys.length;
    for (var start = 0; start < keys.length; start += size) {
      final end = start + size < keys.length ? start + size : keys.length;
      _runChunk(List<K>.unmodifiable(keys.sublist(start, end)), batch);
    }
  }

  void _runChunk(List<K> chunk, Map<K, Completer<R>> batch) {
    Future<Map<K, R>>.sync(() => _batch(chunk)).then<void>(
      (values) {
        for (final key in chunk) {
          _complete(batch[key]!, key, values);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        for (final key in chunk) {
          batch[key]!.completeError(error, stackTrace);
        }
      },
    );
  }

  void _complete(Completer<R> completer, K key, Map<K, R> values) {
    if (values.containsKey(key)) {
      completer.complete(values[key] as R);
      return;
    }
    try {
      completer.complete(missing(key));
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }
}
