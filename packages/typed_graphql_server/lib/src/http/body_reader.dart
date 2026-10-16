import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../cancellation/cancel_signal.dart';
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

  /// Reads [body] to its end, or until a limit, an error or [cancelSignal]
  /// stops it; the subscription is cancelled in every case but the end.
  Future<BodyReadResult> read(
    Stream<List<int>> body, {
    CancelSignal? cancelSignal,
  }) => _BodyRead(maxBytes, timeout).run(body, cancelSignal);
}

/// One run of [BodyReader.read]: the state it needs, kept out of the reader
/// so the reader stays a constant.
final class _BodyRead {
  _BodyRead(this._maxBytes, this._timeout);

  final int _maxBytes;
  final Duration _timeout;
  final Completer<BodyReadResult> _completer = Completer<BodyReadResult>();
  // A copying builder: a host may reuse one buffer for every chunk, and a
  // body of many tiny chunks would otherwise keep one view per chunk alive.
  final BytesBuilder _bytes = BytesBuilder();
  // Nullable, not `late`: a synchronous source can deliver (and finish the
  // read) inside `listen`, before this is assigned.
  StreamSubscription<List<int>>? _subscription;
  Timer? _timer;
  void Function()? _removeCancelListener;

  Future<BodyReadResult> run(
    Stream<List<int>> body,
    CancelSignal? cancelSignal,
  ) {
    // Listening first: if it throws (a stream already listened to), no timer
    // has been started and nothing is left running.
    final subscription = body.listen(
      _onChunk,
      onError: (Object _) => _finish(const BodyFailed()),
      onDone: () => _finish(BodyBytes(_bytes.takeBytes())),
      cancelOnError: true,
    );
    _subscription = subscription;
    if (_completer.isCompleted) {
      subscription.cancel().ignore();
      return _completer.future;
    }
    _timer = Timer(_timeout, () => _finish(const BodyTimedOut()));
    // A client that has gone is a failed read, as an aborted connection is.
    _removeCancelListener = cancelSignal?.addListener(
      () => _finish(const BodyFailed()),
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
    _removeCancelListener?.call();
    _subscription?.cancel().ignore();
    _completer.complete(result);
  }
}
