import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/sse_fixture.dart';

const Duration _settle = Duration(milliseconds: 60);

void main() {
  final sse = SseFixture();
  late GraphQLHttpHandler<Ctx> handler;
  late CountingSubscription counting;

  setUp(() {
    handler = sse.http.handler(options: sse.singleOptions());
    counting = CountingSubscription();
  });

  GraphQLHttpHandler<Ctx> countingHandler({
    SingleConnectionOptions limits = const SingleConnectionOptions(),
  }) => sse.http.handlerOver(
    counting.server,
    options: sse.singleOptions(limits: limits),
  );

  Future<StreamReader> connected(
    GraphQLHttpHandler<Ctx> over,
    String token,
  ) async => StreamReader(await over.handle(sse.connect(token)));

  group('operations on a single connection', () {
    test('accept a subscription with 202 and an empty body', () async {
      final token = await sse.reserve(handler);
      final response = await handler.handle(
        sse.operation(token, 'subscription { ticks }', id: 'a'),
      );
      expect(response.status, 202);
      expect(await sse.http.text(response), '');
    });

    test('stream the events of a subscription with its id', () async {
      final token = await sse.reserve(handler);
      final reader = await connected(handler, token);
      await handler.handle(
        sse.operation(token, 'subscription { ticks }', id: 'a'),
      );
      expect(await reader.waitFor(3), [
        'event: next\ndata: {"id":"a","payload":{"data":{"ticks":"tick 1"}}}',
        'event: next\ndata: {"id":"a","payload":{"data":{"ticks":"tick 2"}}}',
        'event: complete\ndata: {"id":"a"}',
      ]);
      await reader.cancel();
    });

    test('send a query as one next and a complete', () async {
      final token = await sse.reserve(handler);
      final reader = await connected(handler, token);
      await handler.handle(sse.operation(token, '{ hello }', id: 'q'));
      expect(await reader.waitFor(2), [
        'event: next\ndata: {"id":"q","payload":{"data":{"hello":"world"}}}',
        'event: complete\ndata: {"id":"q"}',
      ]);
      await reader.cancel();
    });

    test('interleave two operations on one stream', () async {
      final token = await sse.reserve(handler);
      final reader = await connected(handler, token);
      await handler.handle(
        sse.operation(token, 'subscription { ticks }', id: 'a'),
      );
      await handler.handle(sse.operation(token, '{ hello }', id: 'b'));
      final frames = await reader.waitFor(5);
      List<String> of(String id) => [
        for (final frame in frames)
          if (frame.contains('"id":"$id"')) frame.split('\n').first,
      ];
      expect(of('a'), ['event: next', 'event: next', 'event: complete']);
      expect(of('b'), ['event: next', 'event: complete']);
      await reader.cancel();
    });

    test('hold a result until the stream connects', () async {
      final token = await sse.reserve(handler);
      final response = await handler.handle(
        sse.operation(token, '{ hello }', id: 'q'),
      );
      expect(response.status, 202);
      final reader = await connected(handler, token);
      expect(await reader.waitFor(2), [
        'event: next\ndata: {"id":"q","payload":{"data":{"hello":"world"}}}',
        'event: complete\ndata: {"id":"q"}',
      ]);
      await reader.cancel();
    });

    test('free the id once the operation completed', () async {
      final token = await sse.reserve(handler);
      final reader = await connected(handler, token);
      await handler.handle(sse.operation(token, '{ hello }', id: 'q'));
      await reader.waitFor(2);
      final again = await handler.handle(
        sse.operation(token, '{ hello }', id: 'q'),
      );
      expect(again.status, 202);
      await reader.cancel();
    });

    test('answer a request error on the POST, not on the stream', () async {
      final token = await sse.reserve(handler);
      final reader = await connected(handler, token);
      final response = await handler.handle(
        sse.operation(token, '{ nope }', id: 'q'),
      );
      expect(response.status, 422);
      expect(await sse.http.code(response), 'GQL205');
      await Future<void>.delayed(_settle);
      expect(reader.frames, isEmpty);
      await reader.cancel();
    });
  });

  group('refusals of an operation', () {
    test('an unknown token is 404 GQL433', () async {
      final response = await handler.handle(
        sse.operation('nope', '{ hello }', id: 'q'),
      );
      expect(response.status, 404);
      expect(await sse.http.code(response), 'GQL433');
    });

    test('a missing operation id is 400 GQL435', () async {
      final token = await sse.reserve(handler);
      final response = await handler.handle(
        sse.operation(token, '{ hello }', id: null),
      );
      expect(response.status, 400);
      expect(await sse.http.code(response), 'GQL435');
      expect(
        await sse.http.message(response),
        'A request on an event stream needs extensions.operationId.',
      );
    });

    test('an operation id that is not a string is 400 GQL435', () async {
      final token = await sse.reserve(handler);
      final response = await handler.handle(
        sse.operation(token, '{ hello }', id: 7),
      );
      expect(response.status, 400);
      expect(await sse.http.code(response), 'GQL435');
    });

    test('an empty operation id is 400 GQL435', () async {
      final token = await sse.reserve(handler);
      final response = await handler.handle(
        sse.operation(token, '{ hello }', id: ''),
      );
      expect(await sse.http.code(response), 'GQL435');
    });

    test('an id that is running is 409 GQL436', () async {
      final over = countingHandler();
      final token = await sse.reserve(over);
      final reader = await connected(over, token);
      await over.handle(sse.operation(token, 'subscription { count }'));
      final response = await over.handle(
        sse.operation(token, 'subscription { count }'),
      );
      expect(response.status, 409);
      expect(await sse.http.code(response), 'GQL436');
      expect(
        await sse.http.message(response),
        'An operation with this id is already running.',
      );
      await reader.cancel();
    });

    test('an operation past the maximum is 409 GQL438', () async {
      final over = countingHandler(
        limits: const SingleConnectionOptions(maxOperationsPerStream: 1),
      );
      final token = await sse.reserve(over);
      final reader = await connected(over, token);
      await over.handle(sse.operation(token, 'subscription { count }'));
      final response = await over.handle(
        sse.operation(token, 'subscription { count }', id: 'second'),
      );
      expect(response.status, 409);
      expect(await sse.http.code(response), 'GQL438');
      expect(
        await sse.http.message(response),
        'The event stream runs too many operations.',
      );
      await reader.cancel();
    });

    test('a batch is 422 GQL428', () async {
      final batching = sse.http.handler(
        options: sse.singleOptions(batching: const BatchPolicy()),
      );
      final token = await sse.reserve(batching);
      final response = await batching.handle(
        sse.http.post(
          [
            {'query': '{ hello }'},
          ],
          headers: {SseFixture.tokenHeader: token},
        ),
      );
      expect(response.status, 422);
      expect(await sse.http.code(response), 'GQL428');
      expect(
        await sse.http.message(response),
        'A batch cannot run on an event stream.',
      );
    });
  });

  group('cancelling', () {
    test('DELETE stops the resolvers of the operation', () async {
      final over = countingHandler();
      final token = await sse.reserve(over);
      final reader = await connected(over, token);
      await over.handle(sse.operation(token, 'subscription { count }'));
      await reader.waitFor(2);
      final response = await over.handle(sse.cancel(token, id: 'op'));
      expect(response.status, 200);
      await Future<void>.delayed(_settle);
      final resolved = counting.resolved;
      await Future<void>.delayed(_settle);
      expect(counting.resolved, resolved);
      await reader.cancel();
    });

    test('DELETE sends no complete', () async {
      final over = countingHandler();
      final token = await sse.reserve(over);
      final reader = await connected(over, token);
      await over.handle(sse.operation(token, 'subscription { count }'));
      await reader.waitFor(1);
      await over.handle(sse.cancel(token, id: 'op'));
      await Future<void>.delayed(_settle);
      expect(reader.frames, everyElement(startsWith('event: next')));
      await reader.cancel();
    });

    test('DELETE of an unknown id is 200', () async {
      final token = await sse.reserve(handler);
      final response = await handler.handle(sse.cancel(token, id: 'none'));
      expect(response.status, 200);
    });

    test('DELETE with an unknown token is 404 GQL433', () async {
      final response = await handler.handle(sse.cancel('nope', id: 'a'));
      expect(response.status, 404);
      expect(await sse.http.code(response), 'GQL433');
    });

    test('DELETE without an operation id is 400 GQL435', () async {
      final token = await sse.reserve(handler);
      final response = await handler.handle(sse.cancel(token));
      expect(response.status, 400);
      expect(await sse.http.code(response), 'GQL435');
    });

    test('DELETE of a held operation cancels it before the connect', () async {
      final over = countingHandler();
      final token = await sse.reserve(over);
      await over.handle(sse.operation(token, 'subscription { count }'));
      await over.handle(sse.cancel(token, id: 'op'));
      final reader = await connected(over, token);
      await Future<void>.delayed(_settle);
      expect(counting.resolved, 0);
      expect(reader.frames, isEmpty);
      await reader.cancel();
    });

    test('closing the stream stops every operation', () async {
      final over = countingHandler();
      final token = await sse.reserve(over);
      final reader = await connected(over, token);
      await over.handle(sse.operation(token, 'subscription { count }'));
      await over.handle(
        sse.operation(token, 'subscription { count }', id: 'other'),
      );
      await reader.waitFor(2);
      await reader.cancel();
      await Future<void>.delayed(_settle);
      final resolved = counting.resolved;
      await Future<void>.delayed(_settle);
      expect(counting.resolved, resolved);
    });

    test('an operation held before the connect does not run', () async {
      final over = countingHandler();
      final token = await sse.reserve(over);
      await over.handle(sse.operation(token, 'subscription { count }'));
      await Future<void>.delayed(_settle);
      expect(counting.resolved, 0);
    });
  });
}
