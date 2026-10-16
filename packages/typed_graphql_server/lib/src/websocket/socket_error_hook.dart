import 'dart:async';

/// Sees an unexpected error of a graphql-ws connection: a throw of the
/// `onConnect` hook, of the server pipeline or of an operation's stream.
///
/// The handler reports the error here and then answers the client with a
/// fixed message or close code, never with the error's text. An [Error] is
/// reported too and is never rethrown into the zone: this is a boundary
/// catch, so one broken connection cannot take the process down. A hook that
/// throws is ignored, and so is the failure of the [Future] an `async` hook
/// returns.
///
/// {@category websocket}
typedef SocketErrorHook = FutureOr<void> Function(
  Object error,
  StackTrace stackTrace,
);
