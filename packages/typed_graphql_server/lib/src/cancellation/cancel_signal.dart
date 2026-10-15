import 'dart:async';

import 'package:meta/meta.dart';

/// A request to stop work, created and cancelled by the caller.
///
/// Pass one in `ExecutionOptions.cancelSignal`; the executor listens to it
/// and never cancels it. It has no tie to a transport or a platform, so an
/// HTTP adapter, a WebSocket handler or a test can all cancel the same way.
///
/// {@category cancellation}
final class CancelSignal {
  /// Creates a signal that is not cancelled.
  CancelSignal();

  final Completer<void> _completer = Completer<void>();
  List<void Function()>? _listeners;
  bool _isCancelled = false;
  Object? _reason;

  /// Whether [cancel] has been called.
  bool get isCancelled => _isCancelled;

  /// What the first [cancel] was given, null before it or without a reason.
  Object? get reason => _reason;

  /// Completes, never with an error, when the signal is cancelled; already
  /// complete for a signal that was.
  Future<void> get whenCancelled => _completer.future;

  /// How many listeners wait for the signal.
  @visibleForTesting
  int get listenerCount => _listeners?.length ?? 0;

  /// Cancels the signal with an optional [reason]. Only the first call has
  /// an effect.
  void cancel([Object? reason]) {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _reason = reason;
    final listeners = _listeners;
    _listeners = null;
    _completer.complete();
    if (listeners != null) {
      for (final listener in listeners) {
        listener();
      }
    }
  }

  /// Calls [listener] at once when the signal is cancelled, else when it
  /// is; returns a function that removes the listener. Unlike
  /// [whenCancelled] it leaves nothing behind once removed.
  ///
  /// A listener must not throw: [cancel] calls them in turn and one that
  /// throws would keep the rest from running. Every listener is the
  /// library's own, written not to.
  @internal
  void Function() addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return () {};
    }
    (_listeners ??= []).add(listener);
    return () => _listeners?.remove(listener);
  }
}
