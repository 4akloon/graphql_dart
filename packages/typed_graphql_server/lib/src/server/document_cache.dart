import 'dart:collection';

import 'package:meta/meta.dart';

import 'document_compiler.dart';
import 'document_hash.dart';
import 'document_result.dart';

/// A least-recently-used cache of compiled documents, keyed by the SHA-256 of
/// the text (R5.2).
///
/// The key is computed here from the text, never taken from a client, so a
/// client-sent hash cannot poison the cache. Failures are cached too.
@internal
final class DocumentCache {
  /// Creates a cache of at most [capacity] entries; 0 stores nothing.
  DocumentCache(this.capacity) {
    if (capacity < 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must not be negative');
    }
  }

  /// The most entries the cache holds.
  final int capacity;

  // Dart's default map keeps insertion order: the first key is the oldest.
  final LinkedHashMap<String, DocumentResult> _entries =
      LinkedHashMap<String, DocumentResult>();

  /// The number of entries held.
  @visibleForTesting
  int get length => _entries.length;

  /// The result for [text]: the stored one, which becomes the most recent, or
  /// the one [compiler] makes, stored unless the capacity is 0.
  DocumentResult resultFor(String text, DocumentCompiler compiler) {
    final hash = const DocumentHash().of(text);
    final stored = _entries.remove(hash);
    if (stored != null) {
      _entries[hash] = stored;
      return stored;
    }
    final result = compiler.compile(text, hash);
    if (capacity > 0) {
      _entries[hash] = result;
      if (_entries.length > capacity) {
        _entries.remove(_entries.keys.first);
      }
    }
    return result;
  }
}
