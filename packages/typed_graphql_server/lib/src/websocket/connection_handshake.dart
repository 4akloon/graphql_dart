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

  /// Whether a `connection_init` was received, also one still being decided.
  bool hasInit = false;

  /// Whether `connection_ack` was sent; operations need it.
  bool isAcknowledged = false;

  /// The payload of the `connection_init` message; null until one arrives
  /// or when it carried none.
  JsonObject? connectionParams;

  Timer? _timer;

  /// Calls [onExpired] when the connection is not acknowledged within
  /// `connectionInitTimeout`.
  void startTimer(void Function() onExpired) {
    _timer = Timer(options.connectionInitTimeout, () {
      if (!isAcknowledged) {
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
  /// [hasInit] is set before the hook runs, so a second message that
  /// arrives while the hook is pending is a second initialisation.
  Future<ConnectionDecision> decide(JsonObject? payload) async {
    hasInit = true;
    connectionParams = payload;
    final hook = options.onConnect;
    if (hook == null) {
      return const AcceptConnection();
    }
    return hook(
      RequestInfo(
        method: upgrade.method,
        uri: upgrade.uri,
        headers: upgrade.headers,
        source: upgrade.source,
        connectionParams: payload,
      ),
    );
  }

  /// Marks the connection acknowledged and stops the timer.
  void acknowledge() {
    isAcknowledged = true;
    stopTimer();
  }
}
