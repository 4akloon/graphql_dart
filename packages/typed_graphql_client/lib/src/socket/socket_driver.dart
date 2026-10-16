import 'dart:async';

import 'package:meta/meta.dart';

import '../client/client_failure.dart';
import 'cancellable_wait.dart';
import 'client_socket.dart';
import 'open_operation.dart';
import 'socket_connection.dart';
import 'socket_end.dart';
import 'socket_operations.dart';
import 'socket_settings.dart';

/// Why an attempt failed in a way the loop may try again, and whether the
/// connection had delivered a result before it did.
typedef _Loss = ({ClientFailure cause, bool hadProgress});

/// Keeps one socket alive for as long as operations are open: it connects,
/// serves the socket, and after a loss reconnects by the policy's rules.
///
/// At most one loop runs; a request after the loop ended (every operation
/// done, or the link gave up) starts a new one.
@internal
final class SocketDriver {
  /// Creates a driver for [_operations] with [_settings].
  SocketDriver(this._settings, this._operations);

  final SocketSettings _settings;
  final SocketOperations _operations;
  SocketConnection? _connection;
  bool _isRunning = false;
  bool _isStopped = false;
  final CancellableWait _backoff = CancellableWait();

  /// Starts the connection loop unless it runs, or the driver is stopped.
  void ensureRunning() {
    if (_isRunning || _isStopped) {
      return;
    }
    _isRunning = true;
    unawaited(_drive());
  }

  /// Tells the current socket, if acknowledged, to run [operation].
  void subscribe(OpenOperation operation) => _connection?.subscribe(operation);

  /// Tells the current socket the caller dropped the operation [id].
  void complete(String id) => _connection?.complete(id);

  /// Ends the loop for good and closes the socket with 1000.
  Future<void> stop() async {
    _isStopped = true;
    _backoff.cancel();
    await _connection?.close(1000, 'Normal Closure');
  }

  Future<void> _drive() async {
    try {
      await _reconnectLoop();
    } finally {
      _isRunning = false;
      _connection = null;
    }
    // An operation requested while the loop was still running, for instance
    // while it closed an unused socket, found `_isRunning` set and started
    // nothing; this loop is the only one that can serve it.
    if (_isWanted) {
      ensureRunning();
    }
  }

  Future<void> _reconnectLoop() async {
    var failedAttempts = 0;
    while (_isWanted) {
      final loss = await _connectAndServe();
      if (loss == null || _operations.isEmpty) {
        return;
      }
      failedAttempts = (loss.hadProgress ? 0 : failedAttempts) + 1;
      if (!_settings.policy.allowsRetry(failedAttempts)) {
        _operations.failAll(loss.cause);
        return;
      }
      await _backoff.wait(_settings.policy.delayFor(failedAttempts));
    }
  }

  bool get _isWanted => !_isStopped && !_operations.isEmpty;

  /// One attempt: null when the loop must stop (the operations have been
  /// told why, or the link is disposed), else what to try again after.
  Future<_Loss?> _connectAndServe() async {
    // `then` with `onError` takes whatever `connect` throws, an `Error`
    // included, without a `catch` (the rules forbid catching `Error`).
    final attempt = await Future.sync(_settings.connect).then<Object>(
      (socket) => socket,
      onError: (Object error) => error,
    );
    if (attempt is! ClientSocket) {
      return (
        cause: NetworkFailure(
          attempt is Exception ? attempt : Exception('$attempt'),
        ),
        hadProgress: false,
      );
    }
    final socket = attempt;
    if (_isStopped || _operations.isEmpty) {
      await _closeUnused(socket);
      return null;
    }
    final connection = SocketConnection(socket, _settings, _operations);
    _connection = connection;
    final end = await connection.run();
    _connection = null;
    return _lossFor(end, connection.hasReceivedResult);
  }

  /// A socket that opened after the link was disposed or no longer needed.
  Future<void> _closeUnused(ClientSocket socket) async {
    // The socket may already be gone, and a failing close must not escape;
    // `then` with `onError` also takes an `Error`, which a `catch` may not.
    await Future.sync(() => socket.close(1000, 'Normal Closure')).then<void>(
      (_) {},
      onError: (Object _) {},
    );
  }

  _Loss? _lossFor(SocketEnd end, bool hadResult) {
    switch (end) {
      case AckTimedOut():
        _operations.failAll(
          const SocketFailure(
            .connectionAckTimeout,
            'The server did not acknowledge the connection in time.',
          ),
        );
        return null;
      case MalformedMessage(:final reason):
        _operations.failAll(
          SocketFailure(.malformedSocketMessage, 'Invalid message: $reason'),
        );
        return null;
      case final ConnectionLost lost:
        return _lossAfter(lost, hadResult);
    }
  }

  _Loss? _lossAfter(ConnectionLost lost, bool hadResult) {
    if (_isStopped) {
      return null;
    }
    final failure = SocketFailure(
      .socketClosed,
      lost.message,
      closeCode: lost.closeCode,
      closeReason: lost.closeReason,
    );
    if (_settings.policy.isFatal(lost.closeCode)) {
      _operations.failAll(failure);
      return null;
    }
    _operations
      ..failSentMutations(NetworkFailure(Exception(lost.message)))
      ..markAllUnsent();
    return (cause: failure, hadProgress: hadResult);
  }
}
