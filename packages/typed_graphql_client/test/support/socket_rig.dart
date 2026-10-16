import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import 'fake_socket.dart';

/// The events of one request to a link, recorded as they arrive.
final class RequestProbe {
  /// Listens to [stream].
  RequestProbe(Stream<LinkResult> stream) {
    _subscription = stream.listen(
      results.add,
      onDone: () {
        isDone = true;
        onDone?.call();
      },
    );
  }

  // `late`: assigned in the constructor body, before any event can be read.
  late final StreamSubscription<LinkResult> _subscription;

  /// Every result so far.
  final List<LinkResult> results = [];

  /// Runs when the stream ends, as a listener that reacts to the end.
  void Function()? onDone;

  /// Whether the stream ended.
  bool isDone = false;

  /// The failures among [results].
  List<ClientFailure> get failures => [
    for (final result in results)
      if (result case LinkFailure(:final failure)) failure,
  ];

  /// The payloads among [results].
  List<ResponsePayload> get payloads => [
    for (final result in results)
      if (result case LinkPayload(:final payload)) payload,
  ];

  /// Stops listening, as a caller that cancels its subscription.
  Future<void> cancel() => _subscription.cancel();
}

/// A [WebSocketLink] over [FakeSocketServer] under a fake clock.
///
/// A short backoff (up to 100 ms) keeps the reconnection tests quick.
final class SocketRig {
  /// Creates the rig inside [async].
  SocketRig(
    this.async, {
    JsonObject? connectionParams,
    FutureOr<JsonObject?> Function()? connectionParamsCallback,
    Duration? keepAlive,
    int retryAttempts = 5,
    Duration connectionAckTimeout = const Duration(seconds: 10),
  }) {
    link = WebSocketLink(
      connect: server.connect,
      connectionParams:
          connectionParamsCallback ??
          (connectionParams == null ? null : () => connectionParams),
      connectionAckTimeout: connectionAckTimeout,
      keepAlive: keepAlive,
      retryAttempts: retryAttempts,
      backoff: const Backoff(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 100),
      ),
      random: Random(1),
    );
  }

  /// The fake clock.
  final FakeAsync async;

  /// Where the link connects.
  final FakeSocketServer server = FakeSocketServer();

  /// The link under test.
  // `late`: assigned in the constructor body.
  late final WebSocketLink link;

  /// The probes made, so a test can cancel them all.
  final List<RequestProbe> probes = [];

  /// Sends [operation] through the link and lets the microtasks run.
  RequestProbe request(GraphQLOperation<Object> operation) {
    final probe = RequestProbe(
      link.request(
        LinkRequest.of(operation),
        (request) => Stream.error(StateError('a terminating link forwarded')),
      ),
    );
    probes.add(probe);
    settle();
    return probe;
  }

  /// Runs the microtasks that are due.
  void settle() => async.flushMicrotasks();

  /// Moves the clock by [duration] and runs what became due.
  void elapse(Duration duration) {
    async.elapse(duration);
    settle();
  }

  /// Opens the first socket's handshake: the server acknowledges.
  void acknowledge(FakeSocket socket) {
    socket.serverAcknowledges();
    settle();
  }

  /// The server sends [message] on [socket].
  void serverSends(FakeSocket socket, Map<String, Object?> message) {
    socket.serverSendsJson(message);
    settle();
  }
}
