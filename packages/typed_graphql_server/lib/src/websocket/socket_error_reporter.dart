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
      target(error, stackTrace);
    } on Object {
      // A boundary: a hook that fails must not break the connection that
      // was already being closed or answered because of another error.
    }
  }
}
