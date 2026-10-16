import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/controlled_source.dart';
import 'support/fake_socket.dart';
import 'support/ws_fixture.dart';

void main() {
  const quick = GraphQLWsOptions(
    connectionInitTimeout: Duration(seconds: 5),
    maxOperations: 1,
  );

  Future<FakeSocket> open(
    WsFixture fixture, {
    GraphQLServer<Ctx>? server,
    Map<String, Object?>? params,
  }) async {
    final socket = FakeSocket();
    unawaited(fixture.run(socket, server: server));
    await fixture.init(socket, payload: params);
    return socket;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  group('subscribe', () {
    test('answers a query with next and complete', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ hello }');
      expect(await socket.nextSent(), {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'hello': 'world'},
        },
      });
      expect(await socket.nextSent(), {'type': 'complete', 'id': '1'});
    });

    test('answers a request error with error and no complete', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ nope }');
      final error = await socket.nextSent();
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(error['type'], 'error');
      expect(error['id'], '1');
      expect(error['payload'], isA<List<Object?>>());
      expect(await socket.nextSent(), {'type': 'pong'});
    });

    test('streams a subscription as next messages then complete', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', 'subscription { ticks }');
      final first = await socket.nextSent();
      final second = await socket.nextSent();
      final last = await socket.nextSent();
      expect(first['payload'], {
        'data': {'ticks': 'tick 1'},
      });
      expect(second['payload'], {
        'data': {'ticks': 'tick 2'},
      });
      expect(last, {'type': 'complete', 'id': '1'});
    });

    test('runs a mutation, which needs a POST', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', 'mutation { bump }');
      expect((await socket.nextSent())['payload'], {
        'data': {'bump': 'bumped'},
      });
    });

    test('lets the context factory read the connection parameters', () async {
      final fixture = WsFixture();
      final socket = await open(fixture, params: {'token': 'secret'});
      fixture.subscribe(socket, '1', '{ tag }');
      await socket.nextSent();
      expect(fixture.seenParams, [
        JsonObject({'token': const JsonString('secret')}),
      ]);
    });

    test('closes 4409 for an id in use', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.closed;
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4409,
          'Subscriber for 1 already exists',
        ],
      );
    });

    test('accepts an id again once its operation completed', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.nextSent();
      await socket.nextSent();
      fixture.subscribe(socket, '1', '{ hello }');
      expect((await socket.nextSent())['type'], 'next');
      expect(socket.closeCode, isNull);
    });

    test('answers GQL432 past maxOperations and stays open', () async {
      final fixture = WsFixture(options: quick);
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      fixture.subscribe(socket, '2', '{ hello }');
      final error = await socket.nextSent();
      expect(error['type'], 'error');
      expect(error['id'], '2');
      expect(error['payload'], [
        {
          'message': 'Too many operations are running on this connection.',
          'extensions': {'code': 'GQL432'},
        },
      ]);
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
      expect(socket.closeCode, isNull);
    });

    test('frees a slot when an operation completes', () async {
      final fixture = WsFixture(options: quick);
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.nextSent();
      await socket.nextSent();
      fixture.subscribe(socket, '2', '{ hello }');
      expect((await socket.nextSent())['type'], 'next');
    });
  });

  group('complete', () {
    test('stops a subscription and its source', () async {
      final source = ControlledSource();
      addTearDown(source.close);
      final fixture = WsFixture();
      final socket = await open(fixture, server: source.server());
      fixture.subscribe(socket, '1', 'subscription { events }');
      await settle();
      source.controller.add(1);
      expect((await socket.nextSent())['payload'], {
        'data': {'events': 'event 1'},
      });
      socket.receive(jsonEncode({'type': 'complete', 'id': '1'}));
      await settle();
      expect(source.isCancelled, isTrue);
      expect(socket.sent, hasLength(2));
    });

    test('ignores an unknown id', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      socket.receive(jsonEncode({'type': 'complete', 'id': 'nothing'}));
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
      expect(socket.closeCode, isNull);
    });

    test('sends nothing for a query still pending', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      await settle();
      socket.receive(jsonEncode({'type': 'complete', 'id': '1'}));
      await settle();
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
      expect(socket.sent, hasLength(2));
    });

    test('frees the id for reuse', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      socket.receive(jsonEncode({'type': 'complete', 'id': '1'}));
      fixture.subscribe(socket, '1', '{ hello }');
      expect((await socket.nextSent())['type'], 'next');
      expect(socket.closeCode, isNull);
    });
  });

  group('disconnect', () {
    test('cancels a running subscription', () async {
      final source = ControlledSource();
      addTearDown(source.close);
      final fixture = WsFixture();
      final socket = FakeSocket();
      final done = fixture.run(socket, server: source.server());
      await fixture.init(socket);
      fixture.subscribe(socket, '1', 'subscription { events }');
      await settle();
      await socket.disconnect();
      await done;
      await settle();
      expect(source.isCancelled, isTrue);
    });

    test('cancels the operations when the server closes the socket', () async {
      final source = ControlledSource();
      addTearDown(source.close);
      final fixture = WsFixture();
      final socket = await open(fixture, server: source.server());
      fixture.subscribe(socket, '1', 'subscription { events }');
      await settle();
      socket.receive('not json');
      await socket.closed;
      await settle();
      expect(source.isCancelled, isTrue);
    });
  });
}
