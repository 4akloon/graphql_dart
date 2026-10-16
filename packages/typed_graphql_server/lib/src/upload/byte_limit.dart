import 'dart:async';

import 'package:meta/meta.dart';

import 'byte_limit_exceeded.dart';

/// Counts the bytes of one stream and fails it with [ByteLimitExceeded] when
/// they pass [limit].
///
/// An instance counts one stream: it holds the running total.
@internal
final class ByteLimit extends StreamTransformerBase<List<int>, List<int>> {
  /// Creates a limit of [limit] bytes.
  ByteLimit(this.limit);

  /// The most bytes the stream may carry.
  final int limit;

  int _count = 0;

  /// Counts [length] more bytes and tells whether the total is still within
  /// the limit.
  bool admits(int length) {
    _count += length;
    return _count <= limit;
  }

  /// Passes the chunks of [stream] through until the limit is passed; the
  /// chunk that passes it is not emitted and the source is cancelled.
  @override
  Stream<List<int>> bind(Stream<List<int>> stream) async* {
    await for (final chunk in stream) {
      if (!admits(chunk.length)) throw ByteLimitExceeded(this);
      yield chunk;
    }
  }
}
