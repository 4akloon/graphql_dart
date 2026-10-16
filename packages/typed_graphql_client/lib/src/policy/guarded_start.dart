import 'dart:async';

import 'package:meta/meta.dart';

import '../link/link_result.dart';

/// Listens to a stream of results so that a throwing call becomes an error
/// event followed by the end of the stream (spec section 10, "Stream
/// errors"), not an exception that escapes to the zone.
@internal
final class GuardedStart {
  /// Creates the starter.
  const GuardedStart();

  /// Calls [start], converts each result with [convert] and listens.
  ///
  /// `map` calls [start] (on one trigger event) and [convert] inside the
  /// stream's own try/catch, so a throw, such as a bug in a link or in a
  /// callback of the caller, reaches [onError]. The repo rules forbid
  /// catching `Error`, so no `catch` does it. The trigger is fed after
  /// `listen`, so [start] still runs before this call returns; a throw is
  /// followed by [onDone], and cancelling the subscription cancels the
  /// stream [start] returned.
  StreamSubscription<R> listen<R>(
    Stream<LinkResult> Function() start, {
    required R Function(LinkResult result) convert,
    required void Function(R converted) onData,
    required void Function(Object error, StackTrace stackTrace) onError,
    required void Function() onDone,
  }) {
    final relay = _Relay<R>();
    final trigger = StreamController<void>(sync: true);
    trigger.stream
        .map((_) => start().map(convert))
        .listen(
          relay.follow,
          onError: relay.output.addError,
          onDone: relay.endIfNothingStarted,
        );
    final subscription = relay.output.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
    );
    trigger
      ..add(null)
      ..close();
    return subscription;
  }
}

/// The output of one [GuardedStart.listen] and the stream it follows.
final class _Relay<R> {
  _Relay() {
    output = StreamController<R>(sync: true, onCancel: _cancel);
  }

  // `late` because the controller needs `_cancel`, a member of this object.
  late final StreamController<R> output;
  StreamSubscription<R>? _inner;

  void follow(Stream<R> results) {
    _inner = results.listen(
      output.add,
      onError: output.addError,
      onDone: () {
        // Cleared first: the controller cancels itself when it closes, and
        // would wait for a cancel of a finished stream.
        _inner = null;
        unawaited(output.close());
      },
    );
  }

  void endIfNothingStarted() {
    if (_inner == null) {
      unawaited(output.close());
    }
  }

  Future<void> _cancel() => _inner?.cancel() ?? Future<void>.value();
}
