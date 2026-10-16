import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../http/support/http_fixture.dart';
import '../server/support/server_fixture.dart';
import 'support/sse_fixture.dart';

void main() {
  final sse = SseFixture();
  late GraphQLHttpHandler<Ctx> handler;

  setUp(() => handler = sse.http.handler(options: sse.singleOptions()));

  group('reserving a stream', () {
    test('answers 201 with a plain text token', () async {
      final response = await handler.handle(sse.put());
      expect(response.status, 201);
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
      expect(
        await sse.http.text(response),
        matches(RegExp(r'^[0-9a-f]{32}$')),
      );
    });

    test('accepts any media type with */*', () async {
      final response = await handler.handle(
        sse.put(headers: const {'accept': '*/*'}),
      );
      expect(response.status, 201);
    });

    test('accepts text/* and refuses text/plain with a quality of 0', () async {
      final allowed = await handler.handle(
        sse.put(headers: const {'accept': 'text/*'}),
      );
      final refused = await handler.handle(
        sse.put(headers: const {'accept': 'text/plain;q=0, */*'}),
      );
      expect(allowed.status, 201);
      expect(refused.status, 406);
    });

    test('refuses an Accept that excludes text/plain with GQL422', () async {
      final response = await handler.handle(
        sse.put(headers: HttpFixture.modernClient),
      );
      expect(response.status, 406);
      expect(await sse.http.code(response), 'GQL422');
    });

    test('refuses with 503 GQL437 when the maximum is held', () async {
      handler = sse.http.handler(
        options: sse.singleOptions(
          limits: const SingleConnectionOptions(maxReservations: 1),
        ),
      );
      await handler.handle(sse.put());
      final response = await handler.handle(sse.put());
      expect(response.status, 503);
      expect(await sse.http.code(response), 'GQL437');
      expect(
        await sse.http.message(response),
        'The server holds too many event stream reservations.',
      );
    });
  });

  group('connecting a stream', () {
    test('opens an event stream for the token in the header', () async {
      final token = await sse.reserve(handler);
      final response = await handler.handle(sse.connect(token));
      expect(response.status, 200);
      expect(response.headers['content-type'], startsWith('text/event-stream'));
      await StreamReader(response).cancel();
    });

    test('opens an event stream for the token in the query', () async {
      final token = await sse.reserve(handler);
      final response = await handler.handle(
        sse.connect(token, isInQuery: true),
      );
      expect(response.status, 200);
      await StreamReader(response).cancel();
    });

    test('refuses an unknown token with 404 GQL433', () async {
      final response = await handler.handle(sse.connect('nope'));
      expect(response.status, 404);
      expect(await sse.http.code(response), 'GQL433');
      expect(
        await sse.http.message(response),
        'No event stream is reserved for this token.',
      );
    });

    test('refuses a second connection with 409 GQL434', () async {
      final token = await sse.reserve(handler);
      final first = await handler.handle(sse.connect(token));
      final second = await handler.handle(sse.connect(token));
      expect(second.status, 409);
      expect(await sse.http.code(second), 'GQL434');
      expect(
        await sse.http.message(second),
        'The event stream for this token is already open.',
      );
      await StreamReader(first).cancel();
    });

    test('never completes by itself', () async {
      final token = await sse.reserve(handler);
      final reader = StreamReader(await handler.handle(sse.connect(token)));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(reader.frames, isEmpty);
      expect(reader.isDone, isFalse);
      await reader.cancel();
    });

    test(
      'a POST with the token and an event stream Accept is an operation',
      () async {
        final token = await sse.reserve(handler);
        final post = await handler.handle(
          sse.http.post(
            {
              'query': '{ hello }',
              'extensions': {'operationId': 'a'},
            },
            headers: {
              ...SseFixture.eventStreamClient,
              SseFixture.tokenHeader: token,
            },
          ),
        );
        final get = await handler.handle(sse.connect(token));
        expect(post.status, 202);
        expect(get.status, 200);
        await StreamReader(get).cancel();
      },
    );

    test('drops a reservation nobody connects within the timeout', () async {
      handler = sse.http.handler(
        options: sse.singleOptions(
          limits: const SingleConnectionOptions(
            reservationTimeout: Duration(milliseconds: 20),
          ),
        ),
      );
      final token = await sse.reserve(handler);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final response = await handler.handle(sse.connect(token));
      expect(response.status, 404);
    });

    test('drops the reservation when the client goes away', () async {
      final token = await sse.reserve(handler);
      final reader = StreamReader(await handler.handle(sse.connect(token)));
      await Future<void>.delayed(Duration.zero);
      await reader.cancel();
      final response = await handler.handle(sse.connect(token));
      expect(response.status, 404);
    });

    test('lets a GET with a token and a JSON Accept run as a query', () async {
      final response = await handler.handle(
        sse.http.get(
          {'query': '{ hello }', 'token': 'whatever'},
          headers: {
            ...HttpFixture.preflight,
            ...HttpFixture.modernClient,
          },
        ),
      );
      expect(response.status, 200);
      expect(await sse.http.text(response), '{"data":{"hello":"world"}}');
    });
  });

  group('options', () {
    test('refuse a limit that makes no sense', () {
      for (final limits in const [
        SingleConnectionOptions(maxReservations: 0),
        SingleConnectionOptions(reservationTimeout: Duration.zero),
        SingleConnectionOptions(maxOperationsPerStream: 0),
      ]) {
        expect(
          () => sse.http.handler(options: sse.singleOptions(limits: limits)),
          throwsArgumentError,
        );
      }
    });
  });

  group('methods', () {
    test(
      'answers 405 with PUT and DELETE allowed when the mode is on',
      () async {
        final response = await handler.handle(
          HttpRequestData(method: 'PATCH', uri: Uri.parse('/graphql')),
        );
        expect(response.status, 405);
        expect(response.headers['allow'], 'GET, POST, PUT, DELETE');
      },
    );

    test('refuses PUT with 405 GET, POST when the mode is off', () async {
      final off = sse.http.handler();
      final response = await off.handle(sse.put());
      expect(response.status, 405);
      expect(response.headers['allow'], 'GET, POST');
    });

    test('refuses DELETE with 405 when the mode is off', () async {
      final off = sse.http.handler();
      final response = await off.handle(sse.cancel('t', id: 'a'));
      expect(response.status, 405);
    });
  });
}
