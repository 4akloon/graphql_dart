import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/websocket/server_messages.dart';

void main() {
  const messages = ServerMessages();

  test('connection_ack without a payload has only a type', () {
    expect(messages.ack(null), '{"type":"connection_ack"}');
  });

  test('connection_ack with a payload', () {
    expect(
      messages.ack(JsonObject({'a': JsonNumber(1)})),
      '{"type":"connection_ack","payload":{"a":1}}',
    );
  });

  test('pong without a payload has only a type', () {
    expect(messages.pong(null), '{"type":"pong"}');
  });

  test('pong echoes the payload', () {
    expect(
      messages.pong(JsonObject({'a': const JsonString('b')})),
      '{"type":"pong","payload":{"a":"b"}}',
    );
  });

  test('next writes type, id and payload in that order', () {
    final result = ExecutionResult(JsonObject({'a': JsonNumber(1)}));
    expect(
      messages.next('7', result),
      '{"type":"next","id":"7","payload":{"data":{"a":1}}}',
    );
  });

  test('error writes the errors as an array', () {
    expect(
      messages.error('7', [GraphQLError('boom')]),
      '{"type":"error","id":"7","payload":[{"message":"boom"}]}',
    );
  });

  test('complete has a type and an id', () {
    expect(messages.complete('7'), '{"type":"complete","id":"7"}');
  });

  test('an id with quotes is escaped', () {
    expect(messages.complete('a"b'), r'{"type":"complete","id":"a\"b"}');
  });
}
