import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../http/support/http_fixture.dart';
import 'support/sse_fixture.dart';

void main() {
  final sse = SseFixture();

  group('distinct event streams', () {
    test('stream the events of a subscription and then complete', () async {
      final response = await sse.http.handler().handle(
        sse.postQuery('subscription { ticks }'),
      );
      expect(response.status, 200);
      expect(await sse.frames(response), [
        'event: next\ndata: {"data":{"ticks":"tick 1"}}',
        'event: next\ndata: {"data":{"ticks":"tick 2"}}',
        'event: complete\ndata:',
      ]);
    });

    test('answer with the event stream headers and no connection', () async {
      final response = await sse.http.handler().handle(
        sse.postQuery('subscription { ticks }'),
      );
      expect(response.headers, {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache',
      });
      await sse.http.text(response);
    });

    test('start with a comment', () async {
      final response = await sse.http.handler().handle(
        sse.postQuery('subscription { ticks }'),
      );
      expect((await sse.http.text(response)).startsWith(':\n\n'), isTrue);
    });

    test('send a query as one next and complete', () async {
      final response = await sse.http.handler().handle(
        sse.postQuery('{ hello }'),
      );
      expect(response.status, 200);
      expect(await sse.frames(response), [
        'event: next\ndata: {"data":{"hello":"world"}}',
        'event: complete\ndata:',
      ]);
    });

    test('send a mutation over POST as one next and complete', () async {
      final response = await sse.http.handler().handle(
        sse.postQuery('mutation { bump }'),
      );
      expect(await sse.frames(response), [
        'event: next\ndata: {"data":{"bump":"bumped"}}',
        'event: complete\ndata:',
      ]);
    });

    test('send a validation error as a next event with status 200', () async {
      final response = await sse.http.handler().handle(
        sse.postQuery('{ nope }'),
      );
      expect(response.status, 200);
      final frames = await sse.frames(response);
      expect(frames, hasLength(2));
      expect(frames.first, startsWith('event: next\ndata: {"errors":[{'));
      expect(frames.first, contains('"code":"GQL205"'));
      expect(frames.last, 'event: complete\ndata:');
    });

    test('send a syntax error as a next event with status 200', () async {
      final response = await sse.http.handler().handle(sse.postQuery('{'));
      expect(response.status, 200);
      expect((await sse.frames(response)).first, contains('"errors"'));
    });

    test('serve a subscription over GET', () async {
      final response = await sse.http.handler().handle(
        sse.getStream({'query': 'subscription { ticks }'}),
      );
      expect(response.status, 200);
      expect(await sse.frames(response), hasLength(3));
    });

    test('refuse a mutation over GET with a JSON 405', () async {
      final response = await sse.http.handler().handle(
        sse.getStream({'query': 'mutation { bump }'}),
      );
      expect((response.status, await sse.http.code(response)), (405, 'GQL402'));
      expect(response.headers['allow'], 'POST');
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
    });

    test('keep the headers an extension adds', () async {
      final response = await sse.http
          .handler(extensions: const [HeaderExtension()])
          .handle(sse.postQuery('{ hello }'));
      expect(response.headers['x-extension'], 'yes');
      await sse.http.text(response);
    });

    test('keep a transport refusal before the pipeline as JSON', () async {
      final response = await sse.http.handler().handle(
        sse.http.postBytes(
          utf8.encode('{}'),
          headers: {
            'content-type': 'text/plain',
            ...SseFixture.eventStreamClient,
          },
        ),
      );
      expect((response.status, await sse.http.code(response)), (415, 'GQL421'));
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
    });

    test('refuse a batch with 406 and GQL422', () async {
      final response = await sse.http
          .handler(
            options: const HttpOptions(batching: BatchPolicy()),
          )
          .handle(
            sse.http.post([
              {'query': '{ hello }'},
            ], headers: SseFixture.eventStreamClient),
          );
      expect((response.status, await sse.http.code(response)), (406, 'GQL422'));
      expect(
        await sse.http.message(response),
        'A batch cannot be answered as an event stream.',
      );
    });

    test('are not offered for a multipart POST', () async {
      final response = await sse.http.handler().handle(
        sse.http.postBytes(
          utf8.encode('--b--'),
          headers: {
            'content-type': 'multipart/form-data; boundary=b',
            ...SseFixture.eventStreamClient,
          },
        ),
      );
      expect((response.status, await sse.http.code(response)), (406, 'GQL422'));
    });

    test('are not offered when SSE is off', () async {
      final response = await sse.http
          .handler(options: const HttpOptions(sse: null))
          .handle(sse.postQuery('{ hello }'));
      expect((response.status, await sse.http.code(response)), (406, 'GQL422'));
    });

    test('are not chosen for */*', () async {
      final response = await sse.http.handler().handle(
        sse.http.post({'query': '{ hello }'}, headers: {'accept': '*/*'}),
      );
      expect(
        response.headers['content-type'],
        'application/graphql-response+json; charset=utf-8',
      );
    });

    test('stop the subscription when the body is cancelled', () async {
      final counting = CountingSubscription();
      final handler = sse.http.handlerOver(counting.server);
      final response = await handler.handle(
        sse.postQuery('subscription { count }'),
      );
      final seen = <String>[];
      final subscription = (response.body as StreamedBody).chunks.listen(
        (chunk) => seen.add(utf8.decode(chunk)),
      );
      for (var attempt = 0; attempt < 300; attempt++) {
        if (counting.resolved > 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await subscription.cancel();
      await counting.cancelled.future;
      final resolvedAtCancel = counting.resolved;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(resolvedAtCancel, greaterThan(0));
      expect(counting.resolved, resolvedAtCancel);
    });

    test('refuse a non-positive keep-alive interval', () {
      expect(
        () => sse.http.handler(
          options: const HttpOptions(
            sse: SseOptions(keepAliveInterval: Duration.zero),
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
