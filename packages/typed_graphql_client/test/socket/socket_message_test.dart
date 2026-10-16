import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
// The internal codec is under test, so the tests import it by path.
import 'package:typed_graphql_client/src/socket/socket_message.dart';
import 'package:typed_graphql_client/src/socket/socket_message_codec.dart';

void main() {
  const codec = SocketMessageCodec();

  SocketMessage decoded(SocketMessage message) {
    final result = codec.decode(message.encode());
    if (result case DecodeSuccess(:final value)) {
      return value;
    }
    fail('$message did not decode: $result');
  }

  group('messages a server sends round trip', () {
    test('connection_ack with and without a payload', () {
      expect(
        decoded(const ConnectionAckMessage()).encode(),
        '{"type":"connection_ack"}',
      );
      final withPayload = ConnectionAckMessage(
        JsonObject({'user': const JsonString('ada')}),
      );
      expect(
        decoded(withPayload).encode(),
        '{"type":"connection_ack","payload":{"user":"ada"}}',
      );
    });

    test('ping and pong', () {
      expect(decoded(const PingMessage()), isA<PingMessage>());
      expect(decoded(const PongMessage()), isA<PongMessage>());
      expect(
        decoded(PingMessage(JsonObject({'n': JsonNumber(1)}))).encode(),
        '{"type":"ping","payload":{"n":1}}',
      );
    });

    test('next carries an execution result', () {
      final message = NextMessage(
        '7',
        ExecutionResult(JsonObject({'ticks': JsonNumber(3)})),
      );
      expect(decoded(message), isA<NextMessage>());
      expect(
        decoded(message).encode(),
        '{"type":"next","id":"7","payload":{"data":{"ticks":3}}}',
      );
    });

    test('error carries the errors', () {
      final message = ErrorMessage('2', [GraphQLError('boom')]);
      expect(decoded(message), isA<ErrorMessage>());
      expect(
        decoded(message).encode(),
        '{"type":"error","id":"2","payload":[{"message":"boom"}]}',
      );
    });

    test('complete carries the id', () {
      expect(
        decoded(const CompleteMessage('9')).encode(),
        '{"type":"complete","id":"9"}',
      );
    });
  });

  group('messages a client sends', () {
    test('connection_init writes its payload', () {
      expect(
        ConnectionInitMessage(
          JsonObject({'token': const JsonString('t')}),
        ).encode(),
        '{"type":"connection_init","payload":{"token":"t"}}',
      );
      expect(
        const ConnectionInitMessage().encode(),
        '{"type":"connection_init"}',
      );
    });

    test('subscribe writes the request as its payload', () {
      const message = SubscribeMessage(
        '1',
        GraphQLRequest(query: 'subscription Ticks{ticks}'),
      );
      expect(
        message.encode(),
        '{"type":"subscribe","id":"1",'
        '"payload":{"query":"subscription Ticks{ticks}"}}',
      );
    });

    test('a server cannot send them', () {
      for (final text in [
        '{"type":"connection_init"}',
        '{"type":"subscribe","id":"1","payload":{"query":"{a}"}}',
      ]) {
        expect(codec.decode(text), isA<DecodeFailure>(), reason: text);
      }
    });
  });

  group('hostile texts are failures, never exceptions', () {
    final texts = <String, String>{
      'not JSON': 'nope',
      'empty': '',
      'an array': '[]',
      'a number': '5',
      'a null': 'null',
      'an integer type': '{"type":1}',
      'no type': '{}',
      'unknown type': '{"type":"bogus"}',
      'next without id': '{"type":"next"}',
      'next with a numeric id': '{"type":"next","id":1,"payload":{"data":{}}}',
      'next with a scalar payload': '{"type":"next","id":"1","payload":5}',
      'next without data': '{"type":"next","id":"1","payload":{"errors":[]}}',
      'next without payload': '{"type":"next","id":"1"}',
      'error with no errors': '{"type":"error","id":"1","payload":[]}',
      'error with an object payload': '{"type":"error","id":"1","payload":{}}',
      'error with a bad error': '{"type":"error","id":"1","payload":[{}]}',
      'complete without id': '{"type":"complete"}',
      'ack with a list payload': '{"type":"connection_ack","payload":[]}',
      'ping with a string payload': '{"type":"ping","payload":"x"}',
      'a lone surrogate': '{"type":"\u{D800}"}',
      'deep nesting':
          '{"type":"next","id":"1","payload":'
          '${'[' * 5000}${']' * 5000}}',
    };
    for (final MapEntry(:key, :value) in texts.entries) {
      test(key, () {
        expect(codec.decode(value), isA<DecodeFailure>());
      });
    }
  });

  test('a failure names the payload path', () {
    final result = codec.decode(
      '{"type":"error","id":"1","payload":[{"message":"ok"},{}]}',
    );
    expect(
      result,
      isA<DecodeFailure>().having(
        (failure) => failure.path,
        'path',
        const [PathKey('payload'), PathIndex(1), PathKey('message')],
      ),
    );
  });
}
