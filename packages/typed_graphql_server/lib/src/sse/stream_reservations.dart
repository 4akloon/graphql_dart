import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';

import 'connect_outcome.dart';
import 'single_connection.dart';
import 'single_connection_options.dart';

/// The reservations of single connection mode: tokens that stand for a stream
/// to come (spec section 10).
///
/// A reservation lives until its stream closes, or until
/// [SingleConnectionOptions.reservationTimeout] passes without a connection.
@internal
final class StreamReservations {
  /// Creates an empty store; connected streams send a keep-alive comment every
  /// [keepAliveInterval].
  StreamReservations(this.options, {required this.keepAliveInterval});

  /// The limits.
  final SingleConnectionOptions options;

  /// How long a connected stream may stay silent before a comment is written.
  final Duration keepAliveInterval;

  final Map<String, SingleConnection> _connections = {};
  final Map<String, Timer> _timeouts = {};

  // Secure because the token is the only defence of a stream (spec section
  // 10).
  static final Random _random = Random.secure();

  /// A new token, or null when [SingleConnectionOptions.maxReservations]
  /// reservations are held.
  String? reserve() {
    if (_connections.length >= options.maxReservations) return null;
    final token = _newToken();
    _connections[token] = SingleConnection(onClosed: () => _drop(token));
    _timeouts[token] = Timer(
      options.reservationTimeout,
      () => _connections[token]?.abandon(),
    );
    return token;
  }

  /// Connects the stream of [token].
  ConnectOutcome connect(String token) {
    final connection = _connections[token];
    if (connection == null) return const UnknownToken();
    if (connection.isConnected) return const AlreadyOpen();
    _timeouts.remove(token)?.cancel();
    return Connected(connection.connect(keepAliveInterval));
  }

  void _drop(String token) {
    _connections.remove(token);
    _timeouts.remove(token)?.cancel();
  }

  String _newToken() {
    while (true) {
      final token = [
        for (var i = 0; i < 16; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
      if (!_connections.containsKey(token)) return token;
    }
  }
}
