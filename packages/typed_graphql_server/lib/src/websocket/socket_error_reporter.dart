import 'dart:async';

import 'package:meta/meta.dart';

import 'socket_error_hook.dart';

/// Passes the errors a connection swallowed to the host's
/// [SocketErrorHook], if there is one.
@internal
final class SocketErrorReporter {
  /// Creates a reporter that calls [hook].
  const SocketErrorReporter(this.hook);

  /// The host's hook; null reports nowhere.
  final SocketErrorHook? hook;

  /// Offers [error] to the hook; whatever the hook throws is dropped.
  void report(Object error, StackTrace stackTrace) {
    final target = hook;
    if (target == null) {
      return;
    }
    try {
      final result = target(error, stackTrace);
      if (result is Future<void>) {
        result.ignore();
      }
    } on Object {
      // (guard: a hook that fails must not break the connection that was
      // already being closed or answered because of another error; the
      // error it throws is the hook's own, and the one being reported has
      // already been passed to it, so no Error is hidden.)
    }
  }
}
