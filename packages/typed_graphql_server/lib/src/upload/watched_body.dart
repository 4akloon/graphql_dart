import 'dart:async';

import 'package:meta/meta.dart';
import 'package:mime/mime.dart';

import '../cancellation/cancel_signal.dart';
import 'byte_limit.dart';
import 'byte_limit_exceeded.dart';
import 'part_header_scanner.dart';
import 'part_header_too_large.dart';

/// The failure of a body whose client went away.
final class _Disconnected implements Exception {
  const _Disconnected();
}

/// A request body that reports what goes wrong with it, so that a reader
/// waiting on a part of it never waits forever.
///
/// `package:mime` leaves three failures unreported while a part is being
/// read: the body ends in the middle of a part, the body fails, and the parser
/// throws on a bad header (that error escapes into the zone instead of the
/// stream). Each is recorded here as the one failure of the body, and
/// [guard] and [track] turn it into an error where the reader waits. The body
/// must also stop within a time limit that covers all of it, a failure
/// cancels the host's subscription, which a paused parser would never do, and
/// so does the client going away. The headers of every part are bounded
/// before the parser sees them, because it buffers a header whole.
@internal
final class WatchedBody {
  /// Creates the watch over [source], which may carry [limit] bytes, must
  /// arrive within [timeout] and has part headers within [headers]; the
  /// failure of [cancelSignal], if any, is the failure of the body.
  WatchedBody(
    this._source,
    this._limit,
    this._timeout,
    this._headers, {
    this._cancelSignal,
  });

  final Stream<List<int>> _source;
  final ByteLimit _limit;
  final Duration _timeout;
  final PartHeaderScanner _headers;
  final CancelSignal? _cancelSignal;
  final Completer<Object> _failure = Completer<Object>();
  // `late`: the callbacks are methods of this object, which a field
  // initializer may not name before the object exists.
  late final StreamController<List<int>> _controller =
      StreamController<List<int>>(
        onListen: _start,
        onPause: () => _subscription?.pause(),
        onResume: () => _subscription?.resume(),
        onCancel: cancel,
      );
  StreamSubscription<List<int>>? _subscription;
  Timer? _timer;
  void Function()? _removeCancelListener;

  /// The bytes of the body, within the limit.
  Stream<List<int>> get stream => _controller.stream;

  /// Whether the body has failed.
  bool get hasFailed => _failure.isCompleted;

  /// Waits for [work], or fails with the failure of the body if that comes
  /// first.
  Future<T> guard<T>(Future<T> work) => Future.any<T>([
    work,
    _failure.future.then<T>(Future<T>.error),
  ]);

  /// Records [error] as the failure of the body and stops reading it.
  void fail(Object error) {
    if (_failure.isCompleted) return;
    _failure.complete(error);
    cancel();
  }

  /// Stops reading the host's body and its time limit; calling it again does
  /// nothing.
  void cancel() {
    _timer?.cancel();
    _removeCancelListener?.call();
    _subscription?.cancel().ignore();
  }

  /// Forwards the bytes of [part] and ends with the body's failure if that
  /// comes before the part ends.
  ///
  /// One listener on the failure serves the whole part, however many chunks
  /// it has.
  Stream<List<int>> track(Stream<List<int>> part) {
    StreamSubscription<List<int>>? subscription;
    final forwarded = StreamController<List<int>>();
    var isEnded = false;
    void end([Object? error]) {
      if (isEnded) return;
      isEnded = true;
      if (error != null) forwarded.addError(error);
      forwarded.close().ignore();
      subscription?.cancel().ignore();
    }

    forwarded
      ..onListen = () {
        subscription = part.listen(
          forwarded.add,
          onError: forwarded.addError,
          onDone: end,
        );
        _failure.future.then<void>(end);
      }
      ..onPause = () {
        subscription?.pause();
      }
      ..onResume = () {
        subscription?.resume();
      }
      ..onCancel = () {
        isEnded = true;
        return subscription?.cancel();
      };
    return forwarded.stream;
  }

  void _start() {
    _timer = Timer(_timeout, () => fail(TimeoutException(null, _timeout)));
    _subscription = _source.listen(
      _onChunk,
      onError: fail,
      onDone: _onSourceDone,
      cancelOnError: true,
    );
    _removeCancelListener = _cancelSignal?.addListener(
      () => fail(const _Disconnected()),
    );
  }

  void _onChunk(List<int> chunk) {
    if (_failure.isCompleted) return;
    if (!_limit.admits(chunk.length)) {
      fail(ByteLimitExceeded(_limit));
    } else if (!_headers.admits(chunk)) {
      fail(PartHeaderTooLarge(_headers.maxHeaderBytes));
    } else {
      _controller.add(chunk);
    }
  }

  // A body that stops before its closing delimiter is cut, and package:mime
  // would leave the part it was reading open for ever. The scanner knows the
  // framing, not the pace of the reader, so a slow reader never looks like a
  // cut body.
  void _onSourceDone() {
    _timer?.cancel();
    _controller.close().ignore();
    if (_headers.isCut) {
      fail(const MimeMultipartException('Bad multipart ending'));
    }
  }
}
