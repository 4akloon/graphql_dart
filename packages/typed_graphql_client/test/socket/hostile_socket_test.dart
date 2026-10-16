import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/socket_rig.dart';
import '../support/test_operations.dart';

/// A server that breaks the protocol (spec section 14): every frame ends in a
/// typed failure or is ignored, and nothing escapes as an exception.
void main() {
  void run(String name, void Function(FakeAsync async, SocketRig rig) body) {
    test(name, () {
      fakeAsync((async) {
        body(async, SocketRig(async));
      });
    });
  }

  void expectMalformed(RequestProbe probe, SocketRig rig) {
    expect(probe.failures.single.code, DiagnosticCode.malformedSocketMessage);
    expect(probe.isDone, isTrue);
    expect(rig.server.latest.clientCloseCode, 4400);
    rig.elapse(const Duration(minutes: 1));
    expect(rig.server.connectionCount, 1);
  }

  group('a frame that breaks the protocol after the handshake', () {
    final frames = <String, String>{
      'text that is not JSON': 'not json',
      'a JSON array': '[1, 2]',
      'an unknown type': '{"type":"bogus"}',
      'a next without an id': '{"type":"next","payload":{"data":{}}}',
      'a next with a numeric id': '{"type":"next","id":1,"payload":{}}',
      'an error whose payload is not a list':
          '{"type":"error","id":"1","payload":{"message":"x"}}',
      'a second acknowledgement': '{"type":"connection_ack"}',
    };
    for (final MapEntry(key: name, value: frame) in frames.entries) {
      run('$name closes with 4400 and a typed failure', (async, rig) {
        final probe = rig.request(const TicksSubscription());
        rig.acknowledge(rig.server.latest);
        rig.server.latest.serverSends(frame);
        rig.settle();
        expectMalformed(probe, rig);
      });
    }
  });

  group('a frame at the wrong time', () {
    run('a next before the acknowledgement is a typed failure', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {'data': <String, Object?>{}},
      });
      expectMalformed(probe, rig);
    });

    run('a duplicate complete is ignored', (async, rig) {
      final probe = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig
        ..serverSends(rig.server.latest, {'type': 'complete', 'id': '1'})
        ..serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      expect(probe.failures, isEmpty);
      expect(probe.isDone, isTrue);
      expect(rig.server.latest.isClosedByClient, isFalse);
    });
  });

  group('a flood', () {
    run('of results for unknown ids delivers nothing', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      for (var i = 0; i < 10000; i++) {
        rig.server.latest.serverSendsJson({
          'type': 'next',
          'id': 'ghost-$i',
          'payload': {
            'data': {'ticks': i},
          },
        });
      }
      rig.settle();
      expect(probe.results, isEmpty);
      expect(rig.server.latest.isClosedByClient, isFalse);

      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'ticks': 1},
        },
      });
      expect(probe.payloads, hasLength(1));
    });

    run('of pings gets one pong each and nothing else', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      for (var i = 0; i < 1000; i++) {
        rig.server.latest.serverSendsJson({'type': 'ping'});
      }
      rig.settle();
      expect(rig.server.latest.sentTypes, [
        'connection_init',
        'subscribe',
        ...List.filled(1000, 'pong'),
      ]);
    });
  });

  group('a server that does not finish the handshake', () {
    run('closing before the acknowledgement fails with its code', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.server.latest.serverCloses(4401, 'Unauthorized');
      rig.settle();
      final failure = probe.failures.single as SocketFailure;
      expect(failure.closeCode, 4401);
      expect(probe.isDone, isTrue);
    });

    run('never acknowledging fails with GQL472 and closes with 4504', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.elapse(const Duration(minutes: 1));
      expect(probe.failures.single.code, DiagnosticCode.connectionAckTimeout);
      expect(rig.server.latest.clientCloseCode, 4504);
      expect(rig.server.connectionCount, 1);
    });
  });
}
