import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/controlled_source.dart';
import 'support/fake_socket.dart';
import 'support/ws_fixture.dart';

void main() {
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  Future<void> within(Future<void> future) =>
      future.timeout(const Duration(seconds: 5));

  group('a server close that the peer never answers', () {
    test('ends the session so the connection slot is freed', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(
        fixture.server(),
        options: const GraphQLWsOptions(maxConnections: 1),
      );
      final first = FakeSocket(endsIncomingOnClose: false);
      final firstDone = handler.serve(first, fixture.upgrade());
      first.receive('not json');
      await within(firstDone);
      final second = FakeSocket();
      unawaited(handler.serve(second, fixture.upgrade()));
      second.receive(jsonEncode({'type': 'ping'}));
      expect(await second.nextSent(), {'type': 'pong'});
    });

    test('cancels the operations once the run ended', () async {
      final source = ControlledSource();
      addTearDown(source.close);
      final fixture = WsFixture();
      final socket = FakeSocket(endsIncomingOnClose: false);
      final done = fixture.run(socket, server: source.server());
      await fixture.init(socket);
      fixture.subscribe(socket, '1', 'subscription { events }');
      await settle();
      socket.receive('not json');
      await within(done);
      expect(source.isCancelled, isTrue);
    });

    test('ends the session when the close itself fails', () async {
      final fixture = WsFixture();
      final failing = Completer<void>()
        ..future.ignore()
        ..completeError(StateError('gone'));
      final socket = FakeSocket(
        endsIncomingOnClose: false,
        closeGate: failing.future,
      );
      final done = fixture.run(socket);
      socket.receive('not json');
      await within(done);
    });

    test(
      'cancels the operations at once, before the close completes',
      () async {
        final source = ControlledSource();
        addTearDown(source.close);
        final fixture = WsFixture();
        final closing = Completer<void>();
        final socket = FakeSocket(
          endsIncomingOnClose: false,
          closeGate: closing.future,
        );
        unawaited(fixture.run(socket, server: source.server()));
        await fixture.init(socket);
        fixture.subscribe(socket, '1', 'subscription { events }');
        await settle();
        socket.receive('not json');
        await settle();
        expect(source.isCancelled, isTrue);
        closing.complete();
      },
    );
  });

  group('maxOperations', () {
    test('counts a cancelled operation until its run ended', () async {
      final gate = Completer<void>();
      final fixture = WsFixture(
        options: const GraphQLWsOptions(maxOperations: 1),
      );
      final server = fixture.fixture.server(
        contextFactory: (_) async {
          await gate.future;
          return const Ctx('gated');
        },
      );
      final socket = FakeSocket();
      unawaited(fixture.run(socket, server: server));
      await fixture.init(socket);
      fixture.subscribe(socket, '1', '{ hello }');
      socket.receive(jsonEncode({'type': 'complete', 'id': '1'}));
      fixture.subscribe(socket, '2', '{ hello }');
      final refused = await socket.nextSent();
      expect([refused['type'], refused['id']], ['error', '2']);
      gate.complete();
      await settle();
      fixture.subscribe(socket, '3', '{ hello }');
      expect((await socket.nextSent())['type'], 'next');
    });
  });

  group('a reused id', () {
    test('is not freed by the old operation ending', () async {
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      final gates = [firstGate, secondGate];
      final fixture = WsFixture();
      final server = fixture.fixture.server(
        contextFactory: (_) async {
          await gates.removeAt(0).future;
          return const Ctx('gated');
        },
      );
      final socket = FakeSocket();
      unawaited(fixture.run(socket, server: server));
      await fixture.init(socket);
      fixture.subscribe(socket, '1', '{ hello }');
      socket.receive(jsonEncode({'type': 'complete', 'id': '1'}));
      fixture.subscribe(socket, '1', '{ hello }');
      firstGate.complete();
      await settle();
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.closed;
      expect(socket.closeCode, 4409);
      secondGate.complete();
    });
  });
}
