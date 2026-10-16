import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/fake_socket.dart';
import 'support/ws_fixture.dart';

void main() {
  RequestInfo upgrade(Map<String, String> headers) => RequestInfo(
    method: 'GET',
    uri: Uri.parse('/graphql'),
    headers: headers,
  );

  group('allowsUpgrade', () {
    final fixture = WsFixture();
    final handler = GraphQLWsHandler(
      fixture.server(),
      options: const GraphQLWsOptions(allowedOrigins: ['https://App.Example']),
    );

    bool allows(Map<String, String> headers) =>
        handler.allowsUpgrade(upgrade(headers));

    test('passes an upgrade with no origin', () {
      expect(allows({'host': 'api.example'}), isTrue);
    });

    test('passes the origin of the same host', () {
      expect(
        allows({'origin': 'https://api.example', 'host': 'api.example'}),
        isTrue,
      );
    });

    test('compares the host ignoring case', () {
      expect(
        allows({'origin': 'https://API.example', 'host': 'api.EXAMPLE'}),
        isTrue,
      );
    });

    test('passes a default port the origin leaves out', () {
      expect(
        allows({'origin': 'https://api.example:443', 'host': 'api.example'}),
        isTrue,
      );
    });

    test('refuses the same host on another port', () {
      expect(
        allows({'origin': 'http://api.example:8080', 'host': 'api.example'}),
        isFalse,
      );
    });

    test('refuses another host', () {
      expect(
        allows({'origin': 'https://evil.example', 'host': 'api.example'}),
        isFalse,
      );
    });

    test('passes a listed origin ignoring case', () {
      expect(
        allows({'origin': 'https://app.example', 'host': 'api.example'}),
        isTrue,
      );
    });

    test('refuses the literal null origin', () {
      expect(allows({'origin': 'null', 'host': 'api.example'}), isFalse);
    });

    test('refuses an origin that is not a URI', () {
      expect(allows({'origin': 'a b:%%', 'host': 'api.example'}), isFalse);
    });

    test('refuses an origin with no host', () {
      expect(allows({'origin': 'garbage', 'host': 'garbage'}), isFalse);
    });

    test('refuses an origin when the host header is missing', () {
      expect(allows({'origin': 'https://api.example'}), isFalse);
    });
  });

  group('serve', () {
    test('closes 4406 for another subprotocol', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      final socket = FakeSocket(protocol: 'graphql-ws');
      await handler.serve(socket, fixture.upgrade());
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4406,
          'Subprotocol not acceptable',
        ],
      );
    });

    test('closes 4406 when no subprotocol was negotiated', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      final socket = FakeSocket(protocol: null);
      await handler.serve(socket, fixture.upgrade());
      expect(socket.closeCode, 4406);
    });

    test('closes 4403 for a foreign origin', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      final socket = FakeSocket();
      await handler.serve(
        socket,
        fixture.upgrade(
          headers: {'origin': 'https://evil.example', 'host': 'api.example'},
        ),
      );
      expect([socket.closeCode, socket.closeReason], [4403, 'Forbidden']);
    });

    test('closes 1013 past maxConnections and keeps the first', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(
        fixture.server(),
        options: const GraphQLWsOptions(maxConnections: 1),
      );
      final first = FakeSocket();
      final firstDone = handler.serve(first, fixture.upgrade());
      final second = FakeSocket();
      await handler.serve(second, fixture.upgrade());
      expect([second.closeCode, second.closeReason], [1013, 'Try again later']);
      first.receive(jsonEncode({'type': 'ping'}));
      expect(await first.nextSent(), {'type': 'pong'});
      await first.disconnect();
      await firstDone;
    });

    test('takes a connection again once one ended', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(
        fixture.server(),
        options: const GraphQLWsOptions(maxConnections: 1),
      );
      final first = FakeSocket();
      final firstDone = handler.serve(first, fixture.upgrade());
      await first.disconnect();
      await firstDone;
      final second = FakeSocket();
      unawaited(handler.serve(second, fixture.upgrade()));
      second.receive(jsonEncode({'type': 'ping'}));
      expect(await second.nextSent(), {'type': 'pong'});
    });

    test('serves init, subscribe, next and complete', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      final socket = FakeSocket();
      unawaited(handler.serve(socket, fixture.upgrade()));
      expect(await fixture.init(socket), {'type': 'connection_ack'});
      fixture.subscribe(socket, '7', '{ hello }');
      expect(await socket.nextSent(), {
        'type': 'next',
        'id': '7',
        'payload': {
          'data': {'hello': 'world'},
        },
      });
      expect(await socket.nextSent(), {'type': 'complete', 'id': '7'});
    });

    test('reports what it swallowed to onError', () async {
      final fixture = WsFixture();
      final seen = <Object>[];
      final handler = GraphQLWsHandler(
        fixture.server(),
        options: GraphQLWsOptions(
          onError: (error, stackTrace) => seen.add(error),
        ),
      );
      await handler.serve(ThrowingSocket(), fixture.upgrade());
      expect(seen.single, isA<StateError>());
    });

    test('does not throw when the socket cannot be closed', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      await handler.serve(ThrowingSocket(), fixture.upgrade());
    });
  });

  group('constructor', () {
    final server = WsFixture().server();

    void rejects(GraphQLWsOptions options) => expect(
      () => GraphQLWsHandler(server, options: options),
      throwsArgumentError,
    );

    test('rejects a zero init timeout', () {
      rejects(const GraphQLWsOptions(connectionInitTimeout: Duration.zero));
    });

    test('rejects zero operations', () {
      rejects(const GraphQLWsOptions(maxOperations: 0));
    });

    test('rejects a zero message length', () {
      rejects(const GraphQLWsOptions(maxMessageLength: 0));
    });

    test('rejects a zero id length', () {
      rejects(const GraphQLWsOptions(maxIdLength: 0));
    });

    test('rejects zero connections', () {
      rejects(const GraphQLWsOptions(maxConnections: 0));
    });

    test('rejects a zero JSON depth', () {
      rejects(const GraphQLWsOptions(maxJsonDepth: 0));
    });

    test('rejects a JSON depth past the reader limit', () {
      rejects(const GraphQLWsOptions(maxJsonDepth: 1001));
    });

    test('accepts the default options', () {
      expect(
        GraphQLWsHandler(server).options.maxOperations,
        const GraphQLWsOptions().maxOperations,
      );
    });
  });
}

/// A socket whose close always fails.
final class ThrowingSocket implements GraphQLSocket {
  @override
  String? get protocol => 'other';

  @override
  Stream<String> get incoming => const Stream<String>.empty();

  @override
  void send(String text) {}

  @override
  Future<void> close(int code, String reason) =>
      throw StateError('already closed');
}
