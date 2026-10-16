import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  final hello = LinkRequest.of(const HelloQuery());
  final greet = LinkRequest.of(const GreetQuery('Ada'));

  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  JsonObject? dataOf(LinkResult result) => switch (result) {
    LinkPayload(payload: ExecutionResult(:final data)) => data,
    _ => null,
  };

  test('records every request in order', () async {
    final link = MockLink()
      ..addData(JsonObject(const {}))
      ..addData(JsonObject(const {}));
    await link.request(hello, unterminated).drain<void>();
    await link.request(greet, unterminated).drain<void>();
    expect(
      [
        for (final request in link.requests) request.document.name,
      ],
      ['Hello', 'Greet'],
    );
  });

  test('answers in the order the answers were queued', () async {
    final link = MockLink()
      ..addData(JsonObject({'n': JsonNumber(1)}))
      ..addData(JsonObject({'n': JsonNumber(2)}));
    final first = await link.request(hello, unterminated).single;
    final second = await link.request(hello, unterminated).single;
    expect([first, second].map(dataOf), [
      JsonObject({'n': JsonNumber(1)}),
      JsonObject({'n': JsonNumber(2)}),
    ]);
  });

  test('an answer for an operation skips the others', () async {
    final link = MockLink()
      ..addData(
        JsonObject({'for': const JsonString('Greet')}),
        operationName: 'Greet',
      )
      ..addData(JsonObject({'for': const JsonString('any')}));
    final result = await link.request(hello, unterminated).single;
    expect(dataOf(result), JsonObject({'for': const JsonString('any')}));
    expect(link.pendingAnswerCount, 1);
  });

  test('addErrors queues a request error result', () async {
    final link = MockLink()..addErrors([GraphQLError('bad')]);
    final result = await link.request(hello, unterminated).single;
    expect(
      result,
      isA<LinkPayload>().having(
        (payload) => payload.payload,
        'payload',
        RequestErrorResult(errors: [GraphQLError('bad')]),
      ),
    );
  });

  test('addFailure queues a failure', () async {
    final link = MockLink()..addFailure(const RequestTimedOut(Duration.zero));
    final result = await link.request(hello, unterminated).single;
    expect(
      result,
      isA<LinkFailure>().having(
        (failure) => failure.failure,
        'failure',
        isA<RequestTimedOut>(),
      ),
    );
  });

  test('addStream serves every event of a stream', () async {
    final link = MockLink()
      ..addStream(
        Stream.fromIterable([
          LinkPayload(ExecutionResult(JsonObject({'ticks': JsonNumber(1)}))),
          LinkPayload(ExecutionResult(JsonObject({'ticks': JsonNumber(2)}))),
        ]),
      );
    final results = await link
        .request(LinkRequest.of(const TicksSubscription()), unterminated)
        .toList();
    expect(results, hasLength(2));
  });

  test('a request with no answer gets a StateError', () {
    expect(MockLink().request(hello, unterminated).first, throwsStateError);
  });

  test('an answer for an operation serves that operation', () async {
    final link = MockLink()
      ..addData(
        JsonObject({'for': const JsonString('Greet')}),
        operationName: 'Greet',
      );
    final result = await link.request(greet, unterminated).single;
    expect(dataOf(result), JsonObject({'for': const JsonString('Greet')}));
    expect(link.pendingAnswerCount, 0);
  });

  test('the recorded requests cannot be modified', () {
    final link = MockLink();
    expect(() => link.requests.add(hello), throwsUnsupportedError);
  });
}
