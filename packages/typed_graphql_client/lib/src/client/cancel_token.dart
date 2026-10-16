import 'dart:async';

import 'package:meta/meta.dart';

/// A request to stop a call, created and cancelled by the caller.
///
/// Pass one to `GraphQLClient.query`, `mutate` or `subscribe`; the client
/// listens to it and never cancels it. Cancelling it completes a pending
/// call with a `RequestCancelled` failure and ends the request in every
/// link: with `HttpLink` an HTTP request is aborted, with
/// `WebSocketLink` a subscription is completed.
///
/// {@category client}
final class CancelToken {
  /// Creates a token that is not cancelled.
  CancelToken();

  final Completer<void> _completer = Completer<void>();
  List<void Function()>? _listeners;
  bool _isCancelled = false;
  Object? _reason;

  /// Whether [cancel] has been called.
  bool get isCancelled => _isCancelled;

  /// What the first [cancel] was given, null before it or without a reason.
  Object? get reason => _reason;

  /// Completes, never with an error, when the token is cancelled; already
  /// complete for a token that was.
  Future<void> get whenCancelled => _completer.future;

  /// How many listeners wait for the token.
  @internal
  int get listenerCount => _listeners?.length ?? 0;

  /// Cancels the token with an optional [reason]. Only the first call has
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

  /// Calls [listener] when the token is cancelled, at once when it already
  /// is; returns a function that removes the listener, so a finished call
  /// leaves nothing behind.
  ///
  /// A listener must not throw: [cancel] calls them in turn. Every listener
  /// is the library's own, written not to.
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
