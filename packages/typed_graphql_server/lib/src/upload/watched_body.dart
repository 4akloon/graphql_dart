import 'dart:async';

import 'package:meta/meta.dart';
import 'package:mime/mime.dart';

import 'byte_limit.dart';
import 'byte_limit_exceeded.dart';

/// A request body that reports what goes wrong with it, so that a reader
/// waiting on a part of it never waits forever.
///
/// `package:mime` leaves three failures unreported while a part is being
/// read: the body ends in the middle of a part, the body fails, and the parser
/// throws on a bad header (that error escapes into the zone instead of the
/// stream). Each is recorded here as the one failure of the body, and
/// [guard] and [track] turn it into an error where the reader waits. The body
/// must also stop within a time limit that covers all of it, and a failure
/// cancels the host's subscription, which a paused parser would never do.
@internal
final class WatchedBody {
  /// Creates the watch over [source], which may carry [limit] bytes and must
  /// arrive within [timeout].
  WatchedBody(this._source, this._limit, this._timeout);

  final Stream<List<int>> _source;
  final ByteLimit _limit;
  final Duration _timeout;
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
  bool _isPartOpen = false;

  /// The bytes of the body, within the limit.
  Stream<List<int>> get stream => _controller.stream;

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
    _subscription?.cancel().ignore();
  }

  /// Forwards the bytes of [part] and fails with the body's failure if it
  /// comes before the part ends.
  Stream<List<int>> track(Stream<List<int>> part) {
    _isPartOpen = true;
    return _forward(part);
  }

  Stream<List<int>> _forward(Stream<List<int>> part) async* {
    final iterator = StreamIterator(part);
    try {
      while (await guard(iterator.moveNext())) {
        yield iterator.current;
      }
      _isPartOpen = false;
    } finally {
      await iterator.cancel();
    }
  }

  void _start() {
    _timer = Timer(_timeout, () => fail(TimeoutException(null, _timeout)));
    _subscription = _source.listen(
      _onChunk,
      onError: fail,
      onDone: _onSourceDone,
      cancelOnError: true,
    );
  }

  void _onChunk(List<int> chunk) {
    if (_failure.isCompleted) return;
    if (_limit.admits(chunk.length)) {
      _controller.add(chunk);
    } else {
      fail(ByteLimitExceeded(_limit));
    }
  }

  // The part that ends the body closes in the same parse step that sees the
  // last bytes, but the reader learns of it a few microtasks later, so the
  // check waits for the event loop: a part still open then never ends.
  void _onSourceDone() {
    _timer?.cancel();
    _controller.close().ignore();
    Timer.run(() {
      if (_isPartOpen) {
        fail(const MimeMultipartException('Bad multipart ending'));
      }
    });
  }
}
