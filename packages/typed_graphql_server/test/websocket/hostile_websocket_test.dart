import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/controlled_source.dart';
import 'support/fake_socket.dart';
import 'support/ws_fixture.dart';

void main() {
  const patient = GraphQLWsOptions(
    connectionInitTimeout: Duration(seconds: 5),
  );
  const oneConnection = GraphQLWsOptions(
    connectionInitTimeout: Duration(seconds: 5),
    maxConnections: 1,
  );

  Future<FakeSocket> open(WsFixture fixture) async {
    final socket = FakeSocket();
    unawaited(fixture.run(socket));
    await fixture.init(socket);
    return socket;
  }

  FakeSocket start(WsFixture fixture) {
    final socket = FakeSocket();
    unawaited(fixture.run(socket));
    return socket;
  }

  void expectClosed(FakeSocket socket, int code, String reason) {
    expect(socket.closeCode, code);
    expect(socket.closeReason, reason);
    expect(socket.closeCalls, 1);
  }

  group('before the connection is acknowledged', () {
    test('subscribe before init closes 4401 and runs nothing', () async {
      final fixture = WsFixture(options: patient);
      final socket = start(fixture);
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.closed;
      expectClosed(socket, 4401, 'Unauthorized');
      expect(fixture.contexts, 0);
      expect(socket.sent, isEmpty);
    });

    test('a second init closes 4429', () async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      socket.receive(jsonEncode({'type': 'connection_init'}));
      await socket.closed;
      expectClosed(socket, 4429, 'Too many initialisation requests');
    });

    test('no init closes 4408 after the timeout', () async {
      final fixture = WsFixture(
        options: const GraphQLWsOptions(
          connectionInitTimeout: Duration(milliseconds: 30),
        ),
      );
      final socket = start(fixture);
      await socket.closed;
      expectClosed(socket, 4408, 'Connection initialisation timeout');
      expect(fixture.contexts, 0);
    });

    test('a throwing onConnect closes 4500 without its message', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => throw StateError('secret database password'),
        ),
      );
      final socket = start(fixture);
      socket.receive(jsonEncode({'type': 'connection_init'}));
      await socket.closed;
      expectClosed(socket, 4500, 'Internal server error');
      expect(socket.sent, isEmpty);
    });

    test('an asynchronously throwing onConnect closes 4500', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) async => throw const UnprintableError(),
        ),
      );
      final socket = start(fixture);
      socket.receive(jsonEncode({'type': 'connection_init'}));
      await socket.closed;
      expectClosed(socket, 4500, 'Internal server error');
    });

    test(
      'a connection dropped while onConnect is pending is not acked',
      () async {
        final decision = Completer<ConnectionDecision>();
        final fixture = WsFixture(
          options: GraphQLWsOptions(onConnect: (info) => decision.future),
        );
        final socket = FakeSocket();
        final ended = fixture.run(socket);
        socket.receive(jsonEncode({'type': 'connection_init'}));
        await socket.disconnect();
        await ended;
        decision.complete(const AcceptConnection());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(socket.sent, isEmpty);
      },
    );
  });

  group('unreadable frames', () {
    Future<void> expectInvalid(String frame) async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      socket.receive(frame);
      await socket.closed;
      expectClosed(socket, 4400, 'Invalid message received');
      expect(fixture.contexts, 0);
    }

    test('malformed JSON closes 4400', () => expectInvalid('{"type":'));

    test('JSON nested 100,000 deep closes 4400 quickly', () async {
      final deep = '${'[' * 100000}${']' * 100000}';
      final watch = Stopwatch()..start();
      await expectInvalid(deep);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a payload nested 100,000 deep closes 4400', () async {
      final deep = '${'{"a":' * 100000}1${'}' * 100000}';
      await expectInvalid('{"type":"connection_init","payload":$deep}');
    });

    test('an unknown type closes 4400', () => expectInvalid('{"type":"x"}'));

    test('a message without a type closes 4400', () => expectInvalid('{}'));

    test('next from the client closes 4400', () async {
      await expectInvalid('{"type":"next","id":"1","payload":{}}');
    });

    test('error from the client closes 4400', () async {
      await expectInvalid('{"type":"error","id":"1","payload":[]}');
    });

    test('connection_ack from the client closes 4400', () async {
      await expectInvalid('{"type":"connection_ack"}');
    });

    test('a subscribe without an id closes 4400', () async {
      await expectInvalid('{"type":"subscribe","payload":{"query":"{a}"}}');
    });

    test('an oversized frame closes 1009', () async {
      final fixture = WsFixture(
        options: const GraphQLWsOptions(
          connectionInitTimeout: Duration(seconds: 5),
          maxMessageLength: 64,
        ),
      );
      final socket = await open(fixture);
      socket.receive(
        jsonEncode({
          'type': 'subscribe',
          'id': '1',
          'payload': {'query': '{ hello ${' ' * 100} }'},
        }),
      );
      await socket.closed;
      expectClosed(socket, 1009, 'Message too big');
      expect(fixture.contexts, 0);
    });

    test('frames after a close are ignored', () async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      socket.receive('garbage');
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.closed;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(socket.closeCalls, 1);
      expect(fixture.contexts, 0);
    });
  });

  group('operations', () {
    test('a duplicate id closes 4409', () async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.closed;
      expectClosed(socket, 4409, 'Subscriber for 1 already exists');
      expect(fixture.contexts, 1);
    });

    test('10,000 subscribes past the limit are answered by errors', () async {
      final fixture = WsFixture(
        options: const GraphQLWsOptions(
          connectionInitTimeout: Duration(seconds: 5),
          maxOperations: 5,
        ),
      );
      final socket = await open(fixture);
      for (var i = 0; i < 10000; i++) {
        fixture.subscribe(socket, 'op$i', '{ slow }');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final errors = socket.sent.where((m) => m['type'] == 'error').toList();
      expect(errors, hasLength(9995));
      expect(errors.first['payload'], [
        {
          'message': 'Too many operations are running on this connection.',
          'extensions': {'code': 'GQL432'},
        },
      ]);
      // Only the five that fit were started, so the registry never grew past
      // the limit.
      expect(fixture.contexts, 5);
      expect(socket.closeCalls, 0);
      socket.receive(jsonEncode({'type': 'ping'}));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(socket.sent.last['type'], 'pong');
    });

    test('10,000 pings are answered one for one', () async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      for (var i = 0; i < 10000; i++) {
        socket.receive(
          jsonEncode({
            'type': 'ping',
            'payload': {'n': i},
          }),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final pongs = socket.sent.where((m) => m['type'] == 'pong').toList();
      expect(pongs, hasLength(10000));
      expect(pongs.last['payload'], {'n': 9999});
    });

    test('a disconnect mid-subscription cancels the source', () async {
      final source = ControlledSource();
      final fixture = WsFixture(options: patient);
      final socket = FakeSocket();
      final ended = fixture.run(socket, server: source.server());
      await fixture.init(socket);
      fixture.subscribe(socket, '1', 'subscription { events }');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      source.controller.add(1);
      expect((await socket.nextSent())['type'], 'next');
      await socket.disconnect();
      await ended;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.isCancelled, isTrue);
    });

    test('a close by the server cancels the source', () async {
      final source = ControlledSource();
      final fixture = WsFixture(options: patient);
      final socket = FakeSocket();
      unawaited(fixture.run(socket, server: source.server()));
      await fixture.init(socket);
      fixture.subscribe(socket, '1', 'subscription { events }');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      socket.receive('garbage');
      await socket.closed;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.isCancelled, isTrue);
    });
  });

  group('the handler', () {
    RequestInfo upgrade(Map<String, String> headers) => RequestInfo(
      method: 'GET',
      uri: Uri.parse('/graphql'),
      headers: headers,
    );

    test('a foreign Origin closes 4403 and runs nothing', () async {
      final fixture = WsFixture(options: patient);
      final handler = GraphQLWsHandler<Ctx>(fixture.server());
      final socket = FakeSocket();
      await handler.serve(
        socket,
        upgrade({'origin': 'https://evil.example', 'host': 'api.example'}),
      );
      expectClosed(socket, 4403, 'Forbidden');
      expect(fixture.contexts, 0);
    });

    test('a wrong subprotocol closes 4406', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler<Ctx>(fixture.server());
      final socket = FakeSocket(protocol: 'graphql-ws');
      await handler.serve(socket, fixture.upgrade());
      expectClosed(socket, 4406, 'Subprotocol not acceptable');
    });

    test('a missing subprotocol closes 4406', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler<Ctx>(fixture.server());
      final socket = FakeSocket(protocol: null);
      await handler.serve(socket, fixture.upgrade());
      expectClosed(socket, 4406, 'Subprotocol not acceptable');
    });

    test('more sockets than maxConnections close 1013', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler<Ctx>(
        fixture.server(),
        options: oneConnection,
      );
      final first = FakeSocket();
      unawaited(handler.serve(first, fixture.upgrade()));
      final extra = <FakeSocket>[];
      for (var i = 0; i < 50; i++) {
        final socket = FakeSocket();
        extra.add(socket);
        await handler.serve(socket, fixture.upgrade());
      }
      for (final socket in extra) {
        expectClosed(socket, 1013, 'Try again later');
      }
      first.receive(jsonEncode({'type': 'connection_init'}));
      expect((await first.nextSent())['type'], 'connection_ack');
      await first.disconnect();
    });

    test('a slot is freed when its socket ends', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler<Ctx>(
        fixture.server(),
        options: oneConnection,
      );
      final first = FakeSocket();
      final served = handler.serve(first, fixture.upgrade());
      await first.disconnect();
      await served;
      final second = FakeSocket();
      unawaited(handler.serve(second, fixture.upgrade()));
      second.receive(jsonEncode({'type': 'connection_init'}));
      expect((await second.nextSent())['type'], 'connection_ack');
      await second.disconnect();
    });
  });
}
