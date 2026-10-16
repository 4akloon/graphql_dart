import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_socket.dart';
import '../support/socket_rig.dart';
import '../support/test_operations.dart';

void main() {
  Map<String, Object?> next(String id, int ticks) => {
    'type': 'next',
    'id': id,
    'payload': {
      'data': {'ticks': ticks},
    },
  };

  void run(String name, void Function(FakeAsync async, SocketRig rig) body) {
    test(name, () {
      fakeAsync((async) {
        body(async, SocketRig(async));
      });
    });
  }

  group('the handshake', () {
    run('connects on the first request and not before', (async, rig) {
      expect(rig.server.connectionCount, 0);
      rig.request(const TicksSubscription());
      expect(rig.server.connectionCount, 1);
      expect(rig.server.latest.sentTypes, ['connection_init']);
    });

    run('sends the first operation after the acknowledgement', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentMessages.last, {
        'type': 'subscribe',
        'id': '1',
        'payload': {
          'query': 'subscription Ticks{ticks}',
          'operationName': 'Ticks',
        },
      });
    });

    test('sends the connection parameters', () {
      fakeAsync((async) {
        final rig = SocketRig(
          async,
          connectionParams: JsonObject({'token': const JsonString('t')}),
        )..request(const TicksSubscription());
        expect(rig.server.latest.sentMessages.single, {
          'type': 'connection_init',
          'payload': {'token': 't'},
        });
      });
    });

    run('an operation after the acknowledgement subscribes at once', (
      async,
      rig,
    ) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.request(const HelloQuery());
      expect(rig.server.latest.sentTypes, [
        'connection_init',
        'subscribe',
        'subscribe',
      ]);
    });

    run('fails the waiting operations when no acknowledgement comes', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.elapse(const Duration(seconds: 10));
      expect(rig.server.latest.clientCloseCode, 4504);
      expect(rig.server.latest.clientCloseReason, isNotEmpty);
      expect(probe.failures.single.code, DiagnosticCode.connectionAckTimeout);
      expect(probe.isDone, isTrue);
    });
  });

  group('operations', () {
    run('a query gets its result and ends at complete', (async, rig) {
      final probe = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'hello': 'world'},
        },
      });
      expect(probe.isDone, isFalse);
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      expect(probe.payloads, [
        ExecutionResult(JsonObject({'hello': const JsonString('world')})),
      ]);
      expect(probe.isDone, isTrue);
    });

    run('a subscription gets every result', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      for (var tick = 1; tick <= 3; tick++) {
        rig.serverSends(rig.server.latest, next('1', tick));
      }
      expect(probe.payloads, hasLength(3));
      expect(probe.isDone, isFalse);
    });

    run('an error message is a request error result and ends', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {
        'type': 'error',
        'id': '1',
        'payload': [
          {'message': 'Cannot query field "ticks".'},
        ],
      });
      expect(probe.payloads, [
        RequestErrorResult(
          errors: [GraphQLError('Cannot query field "ticks".')],
        ),
      ]);
      expect(probe.isDone, isTrue);
    });

    run('cancelling before the server completes sends complete', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      probe.cancel();
      rig.settle();
      expect(rig.server.latest.sentMessages.last, {
        'type': 'complete',
        'id': '1',
      });
    });

    run('a finished operation sends no complete when cancelled', (
      async,
      rig,
    ) {
      final probe = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      probe.cancel();
      rig.settle();
      expect(rig.server.latest.sentTypes, ['connection_init', 'subscribe']);
    });

    run('a message for an unknown id is ignored', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, next('99', 1));
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '99'});
      expect(probe.results, isEmpty);
      expect(rig.server.latest.isClosedByClient, isFalse);
    });

    run('two operations share one socket', (async, rig) {
      final first = rig.request(const TicksSubscription());
      final second = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, next('1', 1));
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '2',
        'payload': {
          'data': {'hello': 'x'},
        },
      });
      expect(rig.server.connectionCount, 1);
      expect(first.payloads, hasLength(1));
      expect(second.payloads, hasLength(1));
      expect(
        [
          for (final message in rig.server.latest.sentMessages) message['id'],
        ],
        [null, '1', '2'],
      );
    });

    run('the socket stays open after the last operation ends', (async, rig) {
      rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.latest.isClosedByClient, isFalse);
      rig.request(const HelloQuery());
      expect(rig.server.connectionCount, 1);
    });

    run('a request with files is not supported and sends nothing', (
      async,
      rig,
    ) {
      final probe = RequestProbe(
        rig.link.request(
          LinkRequest.of(
            const GreetQuery('Ada'),
            context: LinkContext([
              UploadFiles([
                UploadFile.fromBytes(const [1], filename: 'a.txt'),
              ]),
            ]),
          ),
          (request) => const Stream.empty(),
        ),
      );
      rig.settle();
      expect(
        probe.failures.single.code,
        DiagnosticCode.operationNotSupportedByLink,
      );
      expect(rig.server.connectionCount, 0);
    });
  });

  group('keeping the socket alive', () {
    run('answers a ping with a pong', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'ping'});
      expect(rig.server.latest.sentMessages.last, {'type': 'pong'});
    });
  });

  group('dispose', () {
    run('closes the socket and cancels the operations', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.link.dispose();
      rig.settle();
      expect(rig.server.latest.clientCloseCode, 1000);
      expect(probe.failures.single, isA<RequestCancelled>());
      expect(probe.isDone, isTrue);
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.connectionCount, 1);
    });

    run('a later request is cancelled and does not connect', (
      async,
      rig,
    ) {
      rig.link.dispose();
      rig.settle();
      final probe = rig.request(const HelloQuery());
      expect(probe.failures.single, isA<RequestCancelled>());
      expect(
        probe.failures.single.code,
        DiagnosticCode.requestCancelled,
      );
      expect(rig.server.connectionCount, 0);
    });
  });

  // Real time, not the fake clock: the client's own futures run in the
  // test's zone.
  test('GraphQLClient.subscribe reads the results', () async {
    final server = FakeSocketServer();
    final client = GraphQLClient(link: WebSocketLink(connect: server.connect));
    final values = <int>[];
    final subscription = client.subscribe(const TicksSubscription()).listen((
      response,
    ) {
      if (response case GraphQLData(:final data)) {
        values.add(data);
      }
    });
    await pumpEventQueue();
    server.latest.serverAcknowledges();
    await pumpEventQueue();
    server.latest
      ..serverSendsJson(next('1', 5))
      ..serverSendsJson(next('1', 6));
    await pumpEventQueue();
    expect(values, [5, 6]);
    await subscription.cancel();
    await pumpEventQueue();
    expect(server.latest.sentTypes.last, 'complete');
  });
}
