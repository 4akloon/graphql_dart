import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/src/socket/socket_message_codec.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/socket_rig.dart';
import '../support/test_operations.dart';

void main() {
  const pause = Duration(milliseconds: 200);

  void run(
    String name,
    void Function(FakeAsync async, SocketRig rig) body, {
    int retryAttempts = 5,
  }) {
    test(name, () {
      fakeAsync((async) {
        body(async, SocketRig(async, retryAttempts: retryAttempts));
      });
    });
  }

  Map<String, Object?> next(String id) => {
    'type': 'next',
    'id': id,
    'payload': {
      'data': {'ticks': 1},
    },
  };

  group('a connect that throws an Error', () {
    run('fails the operations and ends the stream', (async, rig) {
      rig.server.failNext(StateError('bug in connect'));
      final probe = rig.request(const TicksSubscription());
      rig.elapse(pause);
      expect(probe.failures.single, isA<NetworkFailure>());
      expect(probe.isDone, isTrue);
    }, retryAttempts: 0);

    run('is tried again like an Exception', (async, rig) {
      rig.server.failNext(StateError('bug in connect'));
      final probe = rig.request(const TicksSubscription());
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      expect(probe.failures, isEmpty);
    });
  });

  group('a send that throws an Error', () {
    run('does not escape and the loss is still reported', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      final socket = rig.server.latest..sendFailure = StateError('closed sink');
      rig.acknowledge(socket);
      socket.serverCloses(4401, 'unauthorized');
      rig.settle();
      expect(probe.failures.single, isA<SocketFailure>());
      expect(probe.isDone, isTrue);
    });
  });

  group('the reconnection count', () {
    run('is not reset by a connection that only acknowledges', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      for (var i = 0; i < 6 && !probe.isDone; i++) {
        final socket = rig.server.latest;
        rig.acknowledge(socket);
        socket.serverCloses(1012, 'restart');
        rig.elapse(pause);
      }
      expect(probe.isDone, isTrue);
      expect(rig.server.connectionCount, 6);
      expect(probe.failures.single, isA<SocketFailure>());
    });

    run('is reset once a result arrived', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      for (var i = 0; i < 8; i++) {
        final socket = rig.server.latest;
        rig.acknowledge(socket);
        rig.serverSends(socket, next('1'));
        socket.serverCloses(1012, 'restart');
        rig.elapse(pause);
      }
      expect(probe.isDone, isFalse);
      expect(rig.server.connectionCount, 9);
    });
  });

  group('server text in a failure', () {
    test('an unknown message type is clipped to 100 characters', () {
      final result = const SocketMessageCodec().decode(
        '{"type":"${'x' * 5000}"}',
      );
      expect(
        result,
        isA<DecodeFailure>().having(
          (failure) => failure.message.length,
          'message length',
          lessThan(200),
        ),
      );
      expect((result as DecodeFailure).message, contains('...'));
    });
  });
}
