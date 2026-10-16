import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/request_info.dart';
import 'connection_decision.dart';
import 'graphql_ws_options.dart';

/// The state of one connection until it is acknowledged: the initialisation
/// timer, the connection parameters and the `onConnect` hook.
@internal
final class ConnectionHandshake {
  /// Creates the handshake of a connection upgraded by [upgrade].
  ConnectionHandshake(this.options, this.upgrade);

  /// The options of the handler.
  final GraphQLWsOptions options;

  /// The upgrade request the connection came on.
  final RequestInfo upgrade;

  bool _hasInit = false;
  bool _isAcknowledged = false;
  JsonObject? _connectionParams;
  Timer? _timer;

  /// Whether a `connection_init` was received, also one still being decided.
  bool get hasInit => _hasInit;

  /// Whether `connection_ack` was sent; operations need it.
  bool get isAcknowledged => _isAcknowledged;

  /// The payload of the `connection_init` message; null until one arrives
  /// or when it carried none.
  JsonObject? get connectionParams => _connectionParams;

  /// Calls [onExpired] when the connection is not acknowledged within
  /// `connectionInitTimeout`; it covers a slow `onConnect` hook too.
  void startTimer(void Function() onExpired) {
    _timer = Timer(options.connectionInitTimeout, () {
      if (!_isAcknowledged) {
        onExpired();
      }
    });
  }

  /// Stops the timer; calling it again is harmless.
  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Records the `connection_init` and asks the hook (if any) what to do.
  ///
  /// [hasInit] is true before the hook runs, so a second message that
  /// arrives while the hook is pending is a second initialisation.
  Future<ConnectionDecision> decide(JsonObject? payload) async {
    _hasInit = true;
    _connectionParams = payload;
    final hook = options.onConnect;
    if (hook == null) {
      return const AcceptConnection();
    }
    return hook(upgrade.withConnection(payload));
  }

  /// Marks the connection acknowledged and stops the timer.
  void acknowledge() {
    _isAcknowledged = true;
    stopTimer();
  }
}
