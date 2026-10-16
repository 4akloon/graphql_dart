import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/websocket/duplicate_subscriber.dart';
import 'package:typed_graphql_server/src/websocket/ws_close.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  group('GraphQLWsOptions', () {
    const options = GraphQLWsOptions();

    test('waits three seconds for the connection to be initialised', () {
      expect(options.connectionInitTimeout, const Duration(seconds: 3));
    });

    test('runs a hundred operations at most', () {
      expect(options.maxOperations, 100);
    });

    test('accepts a frame of one mebi characters', () {
      expect(options.maxMessageLength, 1048576);
    });

    test('limits the JSON depth to 64', () {
      expect(options.maxJsonDepth, 64);
    });

    test('serves ten thousand connections', () {
      expect(options.maxConnections, 10000);
    });

    test('lists no origin and has no hook', () {
      expect(options.allowedOrigins, isNull);
      expect(options.onConnect, isNull);
    });
  });

  group('ConnectionDecision', () {
    test('accepting carries no payload by default', () {
      expect(const AcceptConnection().payload, isNull);
    });

    test('accepting carries the payload it is given', () {
      final payload = JsonObject({'a': JsonNumber(1)});
      expect(AcceptConnection(payload: payload).payload, payload);
    });

    test('accepting and refusing are the two decisions', () {
      const ConnectionDecision decision = RefuseConnection();
      expect(switch (decision) {
        AcceptConnection() => 'accept',
        RefuseConnection() => 'refuse',
      }, 'refuse');
    });
  });

  group('WsClose', () {
    test('has the codes and reasons of the protocol', () {
      expect(
        {for (final close in WsClose.values) close.code: close.reason},
        {
          4400: 'Invalid message received',
          4401: 'Unauthorized',
          4403: 'Forbidden',
          4406: 'Subprotocol not acceptable',
          4408: 'Connection initialisation timeout',
          4429: 'Too many initialisation requests',
          4500: 'Internal server error',
          1009: 'Message too big',
          1013: 'Try again later',
        },
      );
    });
  });

  group('DuplicateSubscriber', () {
    const duplicate = DuplicateSubscriber();

    test('uses the code 4409', () {
      expect(duplicate.code, 4409);
    });

    test('names a short id in full', () {
      expect(duplicate.reason('7'), 'Subscriber for 7 already exists');
    });

    test('cuts a long id to 123 UTF-8 bytes', () {
      final reason = duplicate.reason('a' * 500);
      expect(utf8.encode(reason), hasLength(123));
      expect(reason, endsWith(' already exists'));
    });

    test('cuts a multi-byte id at a code point boundary', () {
      final reason = duplicate.reason('\u{1F600}' * 100);
      expect(utf8.encode(reason).length, lessThanOrEqualTo(123));
      expect(reason, isNot(contains('�')));
      expect(reason, endsWith('\u{1F600} already exists'));
    });

    test('counts a lone surrogate as the three bytes it is written with', () {
      final reason = duplicate.reason('\uD800' * 100);
      expect(utf8.encode(reason).length, lessThanOrEqualTo(123));
    });
  });
}
