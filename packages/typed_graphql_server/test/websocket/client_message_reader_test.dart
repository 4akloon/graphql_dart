import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/websocket/client_message.dart';
import 'package:typed_graphql_server/src/websocket/client_message_reader.dart';

void main() {
  const reader = ClientMessageReader(8);
  final payload = JsonObject({'token': const JsonString('a')});

  group('connection_init, ping and pong', () {
    test('connection_init without a payload', () {
      expect(
        reader.read('{"type":"connection_init"}'),
        const InitMessage(null),
      );
    });

    test('connection_init with a null payload', () {
      expect(
        reader.read('{"type":"connection_init","payload":null}'),
        const InitMessage(null),
      );
    });

    test('connection_init with an object payload', () {
      expect(
        reader.read('{"type":"connection_init","payload":{"token":"a"}}'),
        InitMessage(payload),
      );
    });

    test('ping with a payload', () {
      expect(
        reader.read('{"type":"ping","payload":{"token":"a"}}'),
        PingMessage(payload),
      );
    });

    test('ping without a payload', () {
      expect(reader.read('{"type":"ping"}'), const PingMessage(null));
    });

    test('pong with a payload', () {
      expect(
        reader.read('{"type":"pong","payload":{"token":"a"}}'),
        PongMessage(payload),
      );
    });

    test('a payload that is an array is invalid', () {
      expect(reader.read('{"type":"connection_init","payload":[]}'), isNull);
    });

    test('a ping payload that is a string is invalid', () {
      expect(reader.read('{"type":"ping","payload":"x"}'), isNull);
    });
  });

  group('subscribe', () {
    test('reads the id and the request', () {
      expect(
        reader.read(
          '{"id":"1","type":"subscribe","payload":{"query":"{a}",'
          '"operationName":"Q","variables":{"x":1}}}',
        ),
        SubscribeMessage(
          '1',
          GraphQLRequest(
            query: '{a}',
            operationName: 'Q',
            variables: JsonObject({'x': JsonNumber(1)}),
          ),
        ),
      );
    });

    test('allows a missing query', () {
      expect(
        reader.read(
          '{"id":"1","type":"subscribe","payload":{"extensions":{}}}',
        ),
        SubscribeMessage('1', GraphQLRequest(extensions: JsonObject({}))),
      );
    });

    test('a missing id is invalid', () {
      expect(
        reader.read('{"type":"subscribe","payload":{"query":"{a}"}}'),
        isNull,
      );
    });

    test('an empty id is invalid', () {
      expect(
        reader.read('{"id":"","type":"subscribe","payload":{"query":"{a}"}}'),
        isNull,
      );
    });

    test('a numeric id is invalid', () {
      expect(
        reader.read('{"id":1,"type":"subscribe","payload":{"query":"{a}"}}'),
        isNull,
      );
    });

    test('a missing payload is invalid', () {
      expect(reader.read('{"id":"1","type":"subscribe"}'), isNull);
    });

    test('a payload that is an array is invalid', () {
      expect(
        reader.read('{"id":"1","type":"subscribe","payload":[]}'),
        isNull,
      );
    });

    test('a mistyped query is invalid', () {
      expect(
        reader.read('{"id":"1","type":"subscribe","payload":{"query":1}}'),
        isNull,
      );
    });
  });

  group('complete', () {
    test('reads the id', () {
      expect(
        reader.read('{"id":"7","type":"complete"}'),
        const CompleteMessage('7'),
      );
    });

    test('an empty id is invalid', () {
      expect(reader.read('{"id":"","type":"complete"}'), isNull);
    });

    test('a missing id is invalid', () {
      expect(reader.read('{"type":"complete"}'), isNull);
    });
  });

  group('invalid frames', () {
    test('text that is not JSON', () {
      expect(reader.read('{"type"'), isNull);
    });

    test('JSON that is not an object', () {
      expect(reader.read('[]'), isNull);
    });

    test('an object without a type', () {
      expect(reader.read('{}'), isNull);
    });

    test('a type that is not a string', () {
      expect(reader.read('{"type":1}'), isNull);
    });

    test('an unknown type', () {
      expect(reader.read('{"type":"hello"}'), isNull);
    });

    test('connection_ack, which only a server sends', () {
      expect(reader.read('{"type":"connection_ack"}'), isNull);
    });

    test('next, which only a server sends', () {
      expect(reader.read('{"id":"1","type":"next","payload":{}}'), isNull);
    });

    test('error, which only a server sends', () {
      expect(reader.read('{"id":"1","type":"error","payload":[]}'), isNull);
    });

    test('JSON deeper than the limit', () {
      final deep = '[' * 9 + ']' * 9;
      expect(reader.read('{"type":"ping","payload":{"a":$deep}}'), isNull);
    });
  });
}
