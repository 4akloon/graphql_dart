import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_socket.dart';
import '../support/socket_rig.dart';
import '../support/test_operations.dart';

void main() {
  const pause = Duration(milliseconds: 200);

  void run(
    String name,
    void Function(FakeAsync async, SocketRig rig) body, {
    FutureOr<JsonObject?> Function()? connectionParamsCallback,
    int retryAttempts = 5,
  }) {
    test(name, () {
      fakeAsync((async) {
        body(
          async,
          SocketRig(
            async,
            connectionParamsCallback: connectionParamsCallback,
            retryAttempts: retryAttempts,
          ),
        );
      });
    });
  }

  group('a socket that fails', () {
    run('is closed, and the next connection is used', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      final first = rig.server.latest..serverFails(Exception('reset'));
      rig.settle();
      expect(first.isClosedByClient, isTrue);
      expect(first.clientCloseCode, 4499);

      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentTypes, ['connection_init', 'subscribe']);
      expect(probe.failures, isEmpty);
    });
  });

  group('a request made while the loop ends', () {
    test('during the closing of an unused socket is served', () {
      fakeAsync((async) {
        final first = Completer<ClientSocket>();
        final unused = FakeSocket()..closeGate = Completer<void>();
        final second = FakeSocket();
        var calls = 0;
        final link = WebSocketLink(
          connect: () {
            calls++;
            return calls == 1 ? first.future : Future.value(second);
          },
        );
        RequestProbe(
          link.request(
            LinkRequest.of(const TicksSubscription()),
            (request) => const Stream<LinkResult>.empty(),
          ),
        ).cancel();
        async.flushMicrotasks();
        first.complete(unused);
        async.flushMicrotasks();
        expect(unused.isClosedByClient, isTrue);

        RequestProbe(
          link.request(
            LinkRequest.of(const HelloQuery()),
            (request) => const Stream<LinkResult>.empty(),
          ),
        );
        async.flushMicrotasks();
        unused.closeGate?.complete();
        async.flushMicrotasks();
        expect(calls, 2);
        expect(second.sentTypes, ['connection_init']);
      });
    });
  });

  group('dispose', () {
    run('during the backoff leaves no timer', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverDrops();
      rig.settle();
      rig.link.dispose();
      rig.settle();
      expect(async.pendingTimers, isEmpty);
      expect(probe.failures.single, isA<RequestCancelled>());
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.connectionCount, 1);
    });

    run('ends a mutation that was sent', (async, rig) {
      final probe = rig.request(const RenameMutation('Ada'));
      rig.acknowledge(rig.server.latest);
      rig.link.dispose();
      rig.settle();
      expect(probe.failures.single, isA<RequestCancelled>());
      expect(probe.isDone, isTrue);
      expect(rig.server.latest.clientCloseCode, 1000);
    });

    test('while connect is pending closes the socket it gets', () {
      fakeAsync((async) {
        final opening = Completer<ClientSocket>();
        final link = WebSocketLink(connect: () => opening.future);
        final probe = RequestProbe(
          link.request(
            LinkRequest.of(const TicksSubscription()),
            (request) => const Stream<LinkResult>.empty(),
          ),
        );
        async.flushMicrotasks();
        link.dispose();
        final socket = FakeSocket();
        opening.complete(socket);
        async.flushMicrotasks();
        expect(socket.clientCloseCode, 1000);
        expect(socket.sent, isEmpty);
        expect(probe.failures.single, isA<RequestCancelled>());
      });
    });
  });

  group('connect', () {
    test('a socket that arrives after every operation left is closed', () {
      fakeAsync((async) {
        final opening = Completer<ClientSocket>();
        final link = WebSocketLink(connect: () => opening.future);
        final probe = RequestProbe(
          link.request(
            LinkRequest.of(const TicksSubscription()),
            (request) => const Stream<LinkResult>.empty(),
          ),
        );
        async.flushMicrotasks();
        probe.cancel();
        async.flushMicrotasks();
        final socket = FakeSocket();
        opening.complete(socket);
        async.flushMicrotasks();
        expect(socket.clientCloseCode, 1000);
        expect(socket.sent, isEmpty);
      });
    });
  });

  group('connectionParams', () {
    run('that throws fails the operations with 4005', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      expect(rig.server.latest.clientCloseCode, 4005);
      final failure = probe.failures.single as SocketFailure;
      expect(failure.code, DiagnosticCode.socketClosed);
      expect(failure.closeCode, 4005);
      expect(rig.server.latest.sent, isEmpty);
    }, connectionParamsCallback: () => throw Exception('no token'));
  });

  group('send', () {
    run('that throws leaves the operation to the reconnection', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.sendFailure = Exception('closing');
      final probe = rig.request(const HelloQuery());
      expect(probe.isDone, isFalse);
      rig.server.latest.serverDrops();
      rig.elapse(pause);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentTypes, [
        'connection_init',
        'subscribe',
        'subscribe',
      ]);
    });
  });

  group('a cancelled operation', () {
    run('ignores a late next', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      probe.cancel();
      rig.settle();
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'ticks': 1},
        },
      });
      expect(probe.results, isEmpty);
      expect(rig.server.latest.isClosedByClient, isFalse);
    });
  });

  group('the configuration', () {
    Future<ClientSocket> connect() async => FakeSocket();

    test('refuses a negative retryAttempts', () {
      expect(
        () => WebSocketLink(connect: connect, retryAttempts: -1),
        throwsArgumentError,
      );
    });

    test('refuses an acknowledgement timeout of zero', () {
      expect(
        () => WebSocketLink(
          connect: connect,
          connectionAckTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('refuses a keep-alive of zero', () {
      expect(
        () => WebSocketLink(connect: connect, keepAlive: Duration.zero),
        throwsArgumentError,
      );
    });

    test('accepts no keep-alive', () {
      expect(() => WebSocketLink(connect: connect), returnsNormally);
    });
  });
}
