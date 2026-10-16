import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/socket_rig.dart';
import '../support/test_operations.dart';

void main() {
  const pause = Duration(milliseconds: 200);

  void run(
    String name,
    void Function(FakeAsync async, SocketRig rig) body, {
    Duration? keepAlive,
    int retryAttempts = 5,
  }) {
    test(name, () {
      fakeAsync((async) {
        body(
          async,
          SocketRig(async, keepAlive: keepAlive, retryAttempts: retryAttempts),
        );
      });
    });
  }

  group('keep-alive', () {
    run('sends a ping every interval', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.elapse(const Duration(seconds: 5));
      expect(rig.server.latest.sentTypes.where((type) => type == 'ping'), [
        'ping',
      ]);
    }, keepAlive: const Duration(seconds: 5));

    run('keeps the socket while pongs arrive', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      for (var i = 0; i < 3; i++) {
        rig.elapse(const Duration(seconds: 5));
        rig.serverSends(rig.server.latest, {'type': 'pong'});
      }
      expect(rig.server.latest.isClosedByClient, isFalse);
    }, keepAlive: const Duration(seconds: 5));

    run('terminates a socket that does not answer and reconnects', (
      async,
      rig,
    ) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.elapse(const Duration(seconds: 10));
      expect(rig.server.sockets.first.clientCloseCode, 4499);
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
    }, keepAlive: const Duration(seconds: 5));
  });

  group('a message the link cannot read', () {
    run('closes with 4400, fails every operation and does not reconnect', (
      async,
      rig,
    ) {
      final first = rig.request(const TicksSubscription());
      final second = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'next', 'id': 1});
      expect(rig.server.latest.clientCloseCode, 4400);
      for (final probe in [first, second]) {
        expect(
          probe.failures.single.code,
          DiagnosticCode.malformedSocketMessage,
        );
        expect(probe.isDone, isTrue);
      }
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.connectionCount, 1);
    });

    run('a second acknowledgement is one too', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.clientCloseCode, 4400);
      expect(
        probe.failures.single.code,
        DiagnosticCode.malformedSocketMessage,
      );
    });

    run('a result before the acknowledgement is one too', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {'data': <String, Object?>{}},
      });
      expect(rig.server.latest.clientCloseCode, 4400);
      expect(probe.failures, hasLength(1));
    });

    run('a text that is not JSON is one too', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverSends('not json');
      rig.settle();
      expect(
        probe.failures.single.code,
        DiagnosticCode.malformedSocketMessage,
      );
    });
  });

  group('a lost connection', () {
    run('resubscribes subscriptions and queries, and fails mutations', (
      async,
      rig,
    ) {
      final ticks = rig.request(const TicksSubscription());
      final hello = rig.request(const HelloQuery());
      final rename = rig.request(const RenameMutation('Ada'));
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverDrops();
      rig.settle();
      expect(rename.failures.single, isA<NetworkFailure>());
      expect(rename.isDone, isTrue);

      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      rig.acknowledge(rig.server.latest);
      expect(
        [
          for (final message in rig.server.latest.sentMessages)
            [message['type'], message['id']],
        ],
        [
          ['connection_init', null],
          ['subscribe', '1'],
          ['subscribe', '2'],
        ],
        reason: 'same ids; the mutation (id 3) is not sent again',
      );
      expect(ticks.isDone, isFalse);
      expect(hello.isDone, isFalse);
    });

    run('keeps delivering results under the same id', (async, rig) {
      final ticks = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverDrops();
      rig.elapse(pause);
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'ticks': 1},
        },
      });
      expect(ticks.payloads, hasLength(1));
    });

    run('sends a mutation that had not been sent when the socket was lost', (
      async,
      rig,
    ) {
      final rename = rig.request(const RenameMutation('Ada'));
      rig.server.latest.serverDrops();
      rig.elapse(pause);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentTypes, ['connection_init', 'subscribe']);
      expect(rename.isDone, isFalse);
    });

    run('does not reconnect when no operation is open', (async, rig) {
      rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      rig.server.latest.serverDrops();
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.connectionCount, 1);
      rig.request(const HelloQuery());
      expect(rig.server.connectionCount, 2);
    });

    run('a code that is never retried fails everything with its code', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverCloses(4401, 'Unauthorized');
      rig.elapse(const Duration(minutes: 1));
      final failure = probe.failures.single;
      expect(failure, isA<SocketFailure>());
      expect(failure.code, DiagnosticCode.socketClosed);
      expect((failure as SocketFailure).closeCode, 4401);
      expect(failure.closeReason, 'Unauthorized');
      expect(rig.server.connectionCount, 1);
      expect(probe.isDone, isTrue);
    });

    run('fails with GQL471 when the attempts run out', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.server.latest.serverCloses(1013, 'Try again later');
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      rig.server.latest.serverCloses(1013, 'Try again later');
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      final failure = probe.failures.single as SocketFailure;
      expect(failure.code, DiagnosticCode.socketClosed);
      expect(failure.closeCode, 1013);
    }, retryAttempts: 1);

    run('a result gives the attempts back', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      for (var i = 0; i < 4; i++) {
        rig.acknowledge(rig.server.latest);
        rig.serverSends(rig.server.latest, {
          'type': 'next',
          'id': '1',
          'payload': {
            'data': {'ticks': 1},
          },
        });
        rig.server.latest.serverDrops();
        rig.elapse(pause);
      }
      expect(rig.server.connectionCount, 5);
      expect(probe.failures, isEmpty);
    }, retryAttempts: 1);
  });

  group('connect', () {
    run('a connect that throws is tried again', (async, rig) {
      rig.server.failNext(Exception('refused'));
      final probe = rig.request(const TicksSubscription());
      expect(rig.server.connectionCount, 1);
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentTypes, ['connection_init', 'subscribe']);
      expect(probe.failures, isEmpty);
    });

    run('a connect that keeps throwing is a network failure', (async, rig) {
      rig.server
        ..failNext(Exception('refused'))
        ..failNext(Exception('refused'));
      final probe = rig.request(const TicksSubscription());
      rig.elapse(pause);
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      expect(probe.failures.single, isA<NetworkFailure>());
      expect(probe.isDone, isTrue);
    }, retryAttempts: 1);

    run('a request after the failure connects again', (async, rig) {
      rig.server.failNext(Exception('refused'));
      rig.request(const HelloQuery());
      rig.elapse(pause);
      rig.request(const HelloQuery());
      expect(rig.server.sockets, hasLength(1));
    }, retryAttempts: 0);
  });
}
