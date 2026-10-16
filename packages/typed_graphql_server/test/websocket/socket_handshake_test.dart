import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/fake_socket.dart';
import 'support/ws_fixture.dart';

void main() {
  const quick = GraphQLWsOptions(
    connectionInitTimeout: Duration(milliseconds: 50),
    maxMessageLength: 200,
  );
  final initText = jsonEncode({'type': 'connection_init'});

  group('connection_init', () {
    test('is acknowledged without a hook', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      expect(await fixture.init(socket), {'type': 'connection_ack'});
    });

    test('is acknowledged with the payload the hook accepts with', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => AcceptConnection(
            payload: JsonObject({'welcome': const JsonString('yes')}),
          ),
        ),
      );
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      expect(await fixture.init(socket), {
        'type': 'connection_ack',
        'payload': {'welcome': 'yes'},
      });
    });

    test('gives the hook the connection parameters and the upgrade', () async {
      RequestInfo? seen;
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) {
            seen = info;
            return const AcceptConnection();
          },
        ),
      );
      final socket = FakeSocket();
      unawaited(
        fixture.run(
          socket,
          upgrade: fixture.upgrade(headers: {'Cookie': 'a=b'}),
        ),
      );
      await fixture.init(socket, payload: {'token': 'secret'});
      expect(
        seen?.connectionParams,
        JsonObject({'token': const JsonString('secret')}),
      );
      expect(seen?.header('cookie'), 'a=b');
      expect(seen?.uri, Uri.parse('/graphql'));
    });

    test('is awaited when the hook is asynchronous', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return const AcceptConnection();
          },
        ),
      );
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      expect(await fixture.init(socket), {'type': 'connection_ack'});
    });

    test('closes 4403 when the hook refuses', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => const RefuseConnection(),
        ),
      );
      final socket = FakeSocket();
      final done = fixture.run(socket);
      socket.receive(initText);
      await done;
      expect([socket.closeCode, socket.closeReason], [4403, 'Forbidden']);
      expect(socket.sent, isEmpty);
    });

    test('closes 4500 when the hook throws', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => throw StateError('database password'),
        ),
      );
      final socket = FakeSocket();
      final done = fixture.run(socket);
      socket.receive(initText);
      await done;
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4500,
          'Internal server error',
        ],
      );
    });

    test('closes 4429 on a second connection_init', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      final done = fixture.run(socket);
      await fixture.init(socket);
      socket.receive(initText);
      await done;
      expect(socket.closeCode, 4429);
    });

    test('closes 4429 on a second init while the hook is pending', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => Completer<ConnectionDecision>().future,
        ),
      );
      final socket = FakeSocket();
      final done = fixture.run(socket);
      socket.receive(initText);
      socket.receive(initText);
      await done;
      expect(socket.closeCode, 4429);
    });

    test('sends nothing when the socket closed while the hook ran', () async {
      final pending = Completer<ConnectionDecision>();
      final fixture = WsFixture(
        options: GraphQLWsOptions(onConnect: (info) => pending.future),
      );
      final socket = FakeSocket();
      final done = fixture.run(socket);
      socket.receive(initText);
      socket.receive(initText);
      await done;
      pending.complete(const AcceptConnection());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(socket.sent, isEmpty);
    });
  });

  group('the connection', () {
    test('closes 4408 when no connection_init arrives in time', () async {
      final socket = FakeSocket();
      await WsFixture(options: quick).run(socket);
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4408,
          'Connection initialisation timeout',
        ],
      );
    });

    test('keeps the timer off once acknowledged', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      await fixture.init(socket);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(socket.closeCode, isNull);
    });

    test('closes 4401 on subscribe before the acknowledgement', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      final done = fixture.run(socket);
      fixture.subscribe(socket, '1', '{ hello }');
      await done;
      expect([socket.closeCode, socket.closeReason], [4401, 'Unauthorized']);
      expect(fixture.contexts, 0);
    });

    test('closes 1009 on a frame longer than the limit', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      socket.receive('x' * 201);
      await done;
      expect([socket.closeCode, socket.closeReason], [1009, 'Message too big']);
    });

    test('closes 4400 on text that is not JSON', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      socket.receive('not json');
      await done;
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4400,
          'Invalid message received',
        ],
      );
    });

    test('closes 4400 on a type only a server sends', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      socket.receive(jsonEncode({'type': 'connection_ack'}));
      await done;
      expect(socket.closeCode, 4400);
    });

    test('answers ping with pong echoing the payload', () async {
      final socket = FakeSocket();
      unawaited(WsFixture(options: quick).run(socket));
      socket.receive(
        jsonEncode({
          'type': 'ping',
          'payload': {'n': 1},
        }),
      );
      expect(await socket.nextSent(), {
        'type': 'pong',
        'payload': {'n': 1},
      });
    });

    test('answers ping without a payload with a bare pong', () async {
      final socket = FakeSocket();
      unawaited(WsFixture(options: quick).run(socket));
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
    });

    test('ignores pong', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      await fixture.init(socket);
      socket.receive(jsonEncode({'type': 'pong'}));
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
      expect(socket.sent, hasLength(2));
    });

    test('ignores frames after it closed and closes once', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      socket.receive('not json');
      socket.receive('more garbage');
      socket.receive(initText);
      await done;
      expect(socket.closeCalls, 1);
      expect(socket.sent, isEmpty);
    });

    test('completes when the socket disconnects', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      await socket.disconnect();
      await done;
      expect(socket.closeCode, isNull);
    });

    test('does not time out after the socket disconnects', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      await socket.disconnect();
      await done;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(socket.closeCalls, 0);
    });
  });
}
