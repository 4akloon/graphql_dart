import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/sse_fixture.dart';

const Duration _settle = Duration(milliseconds: 100);

// A token of the right shape that no reservation holds.
const String _guessed = '00000000000000000000000000000000';

void main() {
  final sse = SseFixture();
  late CountingSubscription counting;

  setUp(() => counting = CountingSubscription());

  GraphQLHttpHandler<Ctx> single({
    SingleConnectionOptions limits = const SingleConnectionOptions(),
  }) => sse.http.handlerOver(
    counting.server,
    options: sse.singleOptions(limits: limits),
  );

  Future<void> expectStopped() async {
    await Future<void>.delayed(_settle);
    final resolved = counting.resolved;
    await Future<void>.delayed(_settle);
    expect(counting.resolved, resolved);
  }

  group('reservations', () {
    test('are refused past the limit, with 503 GQL437', () async {
      final handler = single();
      for (var i = 0; i < 1000; i++) {
        expect((await handler.handle(sse.put())).status, 201);
      }
      final response = await handler.handle(sse.put());
      expect(response.status, 503);
      expect(await sse.http.code(response), 'GQL437');
    });

    test('free their place when the stream closes', () async {
      final handler = single(
        limits: const SingleConnectionOptions(maxReservations: 1),
      );
      final token = await sse.reserve(handler);
      final reader = StreamReader(await handler.handle(sse.connect(token)));
      expect((await handler.handle(sse.put())).status, 503);
      await reader.cancel();
      expect((await handler.handle(sse.put())).status, 201);
    });

    test('a guessed token is 404 GQL433 on every route', () async {
      final handler = single();
      final responses = [
        await handler.handle(sse.connect(_guessed)),
        await handler.handle(sse.connect(_guessed, isInQuery: true)),
        await handler.handle(sse.operation(_guessed, '{ hello }')),
        await handler.handle(sse.cancel(_guessed, id: 'op')),
      ];
      for (final response in responses) {
        expect(response.status, 404);
        expect(await sse.http.code(response), 'GQL433');
      }
      expect(counting.resolved, 0);
    });

    test(
      'a reservation never connected is dropped after the timeout',
      () async {
        final handler = single(
          limits: const SingleConnectionOptions(
            reservationTimeout: Duration(milliseconds: 30),
          ),
        );
        final token = await sse.reserve(handler);
        await Future<void>.delayed(_settle);
        final response = await handler.handle(sse.connect(token));
        expect(response.status, 404);
      },
    );

    test('a dropped reservation cancels its held operations', () async {
      final handler = single(
        limits: const SingleConnectionOptions(
          reservationTimeout: Duration(milliseconds: 30),
        ),
      );
      final token = await sse.reserve(handler);
      final accepted = await handler.handle(
        sse.operation(token, 'subscription { count }'),
      );
      expect(accepted.status, 202);
      await Future<void>.delayed(_settle);
      expect(
        (await handler.handle(sse.operation(token, '{ hello }'))).status,
        404,
      );
      expect(counting.resolved, 0);
    });
  });

  group('a stream', () {
    test('connected twice is 409 GQL434', () async {
      final handler = single();
      final token = await sse.reserve(handler);
      final first = StreamReader(await handler.handle(sse.connect(token)));
      final second = await handler.handle(sse.connect(token));
      expect(second.status, 409);
      expect(await sse.http.code(second), 'GQL434');
      await first.cancel();
    });

    test('connected twice leaves the first connection working', () async {
      final handler = single();
      final token = await sse.reserve(handler);
      final first = StreamReader(await handler.handle(sse.connect(token)));
      await handler.handle(sse.connect(token));
      await handler.handle(sse.operation(token, '{ hello }'));
      expect(await first.waitFor(2), [
        'event: next\ndata: {"id":"op","payload":{"data":{"hello":"world"}}}',
        'event: complete\ndata: {"id":"op"}',
      ]);
      await first.cancel();
    });

    test('refuses operations past the limit with 409 GQL438', () async {
      final handler = single(
        limits: const SingleConnectionOptions(maxOperationsPerStream: 3),
      );
      final token = await sse.reserve(handler);
      final statuses = <int>[];
      String? lastCode;
      for (var i = 0; i < 50; i++) {
        final response = await handler.handle(
          sse.operation(token, 'subscription { count }', id: 'op$i'),
        );
        statuses.add(response.status);
        if (response.status != 202) lastCode = await sse.http.code(response);
      }
      expect(statuses.where((status) => status == 202), hasLength(3));
      expect(statuses.where((status) => status == 409), hasLength(47));
      expect(lastCode, 'GQL438');
    });

    test('runs nothing for the operations a full stream refuses', () async {
      final handler = single(
        limits: const SingleConnectionOptions(maxOperationsPerStream: 1),
      );
      final token = await sse.reserve(handler);
      await handler.handle(sse.operation(token, 'subscription { count }'));
      await handler.handle(
        sse.operation(token, 'subscription { count }', id: 'second'),
      );
      expect(counting.resolved, 0);
    });

    test('refuses a reused operation id and keeps the first', () async {
      final handler = single();
      final token = await sse.reserve(handler);
      final reader = StreamReader(await handler.handle(sse.connect(token)));
      await handler.handle(sse.operation(token, 'subscription { count }'));
      final again = await handler.handle(
        sse.operation(token, 'subscription { count }'),
      );
      expect(again.status, 409);
      expect(await sse.http.code(again), 'GQL436');
      await reader.waitFor(2);
      await reader.cancel();
      await expectStopped();
    });

    test('answers 200 to a DELETE of a stranger without cancelling', () async {
      final handler = single();
      final owner = await sse.reserve(handler);
      final stranger = await sse.reserve(handler);
      final reader = StreamReader(await handler.handle(sse.connect(owner)));
      await handler.handle(sse.operation(owner, 'subscription { count }'));
      final response = await handler.handle(sse.cancel(stranger, id: 'op'));
      expect(response.status, 200);
      await reader.cancel();
    });

    test('keeps the operations of another reservation on DELETE', () async {
      final handler = single();
      final owner = await sse.reserve(handler);
      final stranger = await sse.reserve(handler);
      final reader = StreamReader(await handler.handle(sse.connect(owner)));
      await handler.handle(sse.operation(owner, 'subscription { count }'));
      await reader.waitFor(1);
      await handler.handle(sse.cancel(stranger, id: 'op'));
      final resolved = counting.resolved;
      await Future<void>.delayed(_settle);
      expect(counting.resolved, greaterThan(resolved));
      await reader.cancel();
    });

    test('stops every resolver when the client disconnects', () async {
      final handler = single();
      final token = await sse.reserve(handler);
      final reader = StreamReader(await handler.handle(sse.connect(token)));
      await handler.handle(sse.operation(token, 'subscription { count }'));
      await reader.waitFor(1);
      await reader.cancel();
      await expectStopped();
    });
  });

  group('a slow client', () {
    test('that stops reading stops the resolvers after one event', () async {
      final handler = sse.http.handlerOver(counting.server);
      final response = await handler.handle(
        sse.getStream({'query': 'subscription { count }'}),
      );
      final subscription = (response.body as StreamedBody).chunks.listen(
        (_) {},
      )..pause();
      await Future<void>.delayed(_settle);
      final resolved = counting.resolved;
      expect(resolved, lessThanOrEqualTo(2));
      await Future<void>.delayed(_settle);
      expect(counting.resolved, resolved);
      await subscription.cancel();
    });

    test('that reads again resumes the resolvers', () async {
      final handler = sse.http.handlerOver(counting.server);
      final response = await handler.handle(
        sse.getStream({'query': 'subscription { count }'}),
      );
      final subscription = (response.body as StreamedBody).chunks.listen(
        (_) {},
      )..pause();
      await Future<void>.delayed(_settle);
      final resolved = counting.resolved;
      subscription.resume();
      await Future<void>.delayed(_settle);
      expect(counting.resolved, greaterThan(resolved));
      await subscription.cancel();
    });

    test('that disconnects stops the resolvers of a distinct stream', () async {
      final handler = sse.http.handlerOver(counting.server);
      final response = await handler.handle(
        sse.getStream({'query': 'subscription { count }'}),
      );
      final subscription = (response.body as StreamedBody).chunks.listen(
        (_) {},
      );
      await Future<void>.delayed(_settle);
      expect(counting.resolved, greaterThan(0));
      await subscription.cancel();
      await expectStopped();
    });

    test('whose body nobody listens to runs no operation', () async {
      final handler = single();
      final token = await sse.reserve(handler);
      final response = await handler.handle(sse.connect(token));
      await handler.handle(sse.operation(token, 'subscription { count }'));
      await Future<void>.delayed(_settle);
      // No operation starts until the host listens to the body.
      expect(response.status, 200);
      expect(counting.resolved, 0);
    });
  });

  group('a cross-site request', () {
    test('without a token is an ordinary JSON refusal', () async {
      final handler = single();
      final response = await handler.handle(
        sse.http.postBytes(
          '{"query":"{ hello }"}'.codeUnits,
          headers: {
            ...SseFixture.eventStreamClient,
            'content-type': 'text/plain',
          },
        ),
      );
      expect(response.status, 415);
      expect(response.headers['content-type'], contains('json'));
      expect(sse.http.contexts, 0);
    });

    test('with a token but a form content type runs nothing', () async {
      final handler = single();
      final token = await sse.reserve(handler);
      final reader = StreamReader(await handler.handle(sse.connect(token)));
      final response = await handler.handle(
        sse.http.postBytes(
          'query=%7B+hello+%7D'.codeUnits,
          headers: {
            SseFixture.tokenHeader: token,
            'content-type': 'application/x-www-form-urlencoded',
          },
        ),
      );
      expect(response.status, 415);
      await Future<void>.delayed(_settle);
      expect(reader.frames, isEmpty);
      await reader.cancel();
    });

    test('a GET without the preflight header is 403 in production', () async {
      final handler = sse.http.handler(
        profile: ServerProfile.production,
        options: sse.singleOptions(),
      );
      final response = await handler.handle(
        sse.http.get(
          {'query': '{ hello }'},
          headers: SseFixture.eventStreamClient,
        ),
      );
      expect(response.status, 403);
      expect(await sse.http.code(response), 'GQL403');
    });
  });
}
