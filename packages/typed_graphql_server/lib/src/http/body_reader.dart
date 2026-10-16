import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'body_read_result.dart';

/// Reads a request body into memory without ever holding more than a limit,
/// and without waiting longer than another (R5.5).
///
/// A `content-length` header can lie or be absent, so the count is of the
/// bytes that actually arrive; a client that trickles bytes is stopped by the
/// time limit, which covers the whole body, not each chunk.
@internal
final class BodyReader {
  /// Creates a reader that accepts at most [maxBytes] bytes arriving within
  /// [timeout].
  const BodyReader(this.maxBytes, this.timeout);

  /// The longest body accepted, in bytes.
  final int maxBytes;

  /// How long the whole body may take to arrive.
  final Duration timeout;

  /// Reads [body] to its end, or until a limit or an error stops it; the
  /// subscription is cancelled in every case but the end.
  Future<BodyReadResult> read(Stream<List<int>> body) =>
      _BodyRead(maxBytes, timeout).run(body);
}

/// One run of [BodyReader.read]: the state it needs, kept out of the reader
/// so the reader stays a constant.
final class _BodyRead {
  _BodyRead(this._maxBytes, this._timeout);

  final int _maxBytes;
  final Duration _timeout;
  final Completer<BodyReadResult> _completer = Completer<BodyReadResult>();
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  // `late`: assigned by `run` right after the stream is listened to; no
  // callback can run before `run` returns, because events are asynchronous.
  late final StreamSubscription<List<int>> _subscription;
  Timer? _timer;

  Future<BodyReadResult> run(Stream<List<int>> body) {
    _timer = Timer(_timeout, () => _finish(const BodyTimedOut()));
    _subscription = body.listen(
      _onChunk,
      onError: (Object _) => _finish(const BodyFailed()),
      onDone: () => _finish(BodyBytes(_bytes.takeBytes())),
      cancelOnError: true,
    );
    return _completer.future;
  }

  void _onChunk(List<int> chunk) {
    if (_bytes.length + chunk.length > _maxBytes) {
      _finish(const BodyTooLarge());
      return;
    }
    _bytes.add(chunk);
  }

  void _finish(BodyReadResult result) {
    if (_completer.isCompleted) return;
    _timer?.cancel();
    _subscription.cancel().ignore();
    _completer.complete(result);
  }
}
