import 'dart:collection';

import 'package:meta/meta.dart';

import 'document_compiler.dart';
import 'document_hash.dart';
import 'document_result.dart';

/// A least-recently-used cache of compiled documents, keyed by the text
/// itself (R5.2).
///
/// The key is the text, never a client-sent hash and not its SHA-256: a text
/// with a lone surrogate hashes like the same text with U+FFFD, and must not
/// take that text's entry. Failures are cached too. The cache is bounded by
/// entry count and by the total length of the cached texts, because a
/// compiled document costs memory in proportion to its text.
@internal
final class DocumentCache {
  /// Creates a cache of at most [capacity] entries (0 stores nothing) whose
  /// texts add up to at most [maxTotalLength] characters.
  ///
  /// A text longer than [maxTotalLength] is never cached.
  DocumentCache(this.capacity, {this.maxTotalLength = defaultMaxTotalLength}) {
    if (capacity < 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must not be negative');
    }
    if (maxTotalLength < 0) {
      throw ArgumentError.value(
        maxTotalLength,
        'maxTotalLength',
        'must not be negative',
      );
    }
  }

  /// The default of [maxTotalLength]: 4 million characters.
  static const int defaultMaxTotalLength = 4000000;

  /// The most entries the cache holds.
  final int capacity;

  /// The most characters the cached texts hold together.
  final int maxTotalLength;

  // Dart's default map keeps insertion order: the first key is the oldest.
  final LinkedHashMap<String, DocumentResult> _entries =
      LinkedHashMap<String, DocumentResult>();

  int _totalLength = 0;

  /// The number of entries held.
  @visibleForTesting
  int get length => _entries.length;

  /// The characters of the texts held.
  @visibleForTesting
  int get totalLength => _totalLength;

  /// The result for [text]: the stored one, which becomes the most recent, or
  /// the one [compiler] makes, stored unless it does not fit the bounds.
  DocumentResult resultFor(String text, DocumentCompiler compiler) {
    final stored = _entries.remove(text);
    if (stored != null) {
      _entries[text] = stored;
      return stored;
    }
    final result = compiler.compile(text, const DocumentHash().of(text));
    if (capacity > 0 && text.length <= maxTotalLength) {
      _entries[text] = result;
      _totalLength += text.length;
      _evictOldest();
    }
    return result;
  }

  void _evictOldest() {
    while (_entries.length > capacity || _totalLength > maxTotalLength) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
      _totalLength -= oldest.length;
    }
  }
}
