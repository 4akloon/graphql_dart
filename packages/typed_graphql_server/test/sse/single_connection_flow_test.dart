import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/sse/single_connection.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../http/support/http_fixture.dart';
import '../server/support/server_fixture.dart';
import 'support/sse_fixture.dart';

const Duration _settle = Duration(milliseconds: 100);

void main() {
  final sse = SseFixture();
  late CountingSubscription counting;
  late GraphQLHttpHandler<Ctx> handler;

  setUp(() {
    counting = CountingSubscription();
    handler = sse.http.handlerOver(
      counting.server,
      options: sse.singleOptions(),
    );
  });

  Future<StreamReader> connected(String token) async =>
      StreamReader(await handler.handle(sse.connect(token)));

  Future<int> resolvedAfterSettling() async {
    await Future<void>.delayed(_settle);
    final resolved = counting.resolved;
    await Future<void>.delayed(_settle);
    expect(counting.resolved, resolved);
    return resolved;
  }

  group('a paused single-connection stream', () {
    test('pauses the operations that are running', () async {
      final token = await sse.reserve(handler);
      final reader = await connected(token);
      await handler.handle(sse.operation(token, 'subscription { count }'));
      await reader.waitFor(1);
      reader.pause();
      await resolvedAfterSettling();
      await reader.cancel();
    });

    test('resumes the operations when the client reads again', () async {
      final token = await sse.reserve(handler);
      final reader = await connected(token);
      await handler.handle(sse.operation(token, 'subscription { count }'));
      await reader.waitFor(1);
      reader.pause();
      final paused = await resolvedAfterSettling();
      reader.resume();
      await Future<void>.delayed(_settle);
      expect(counting.resolved, greaterThan(paused));
      await reader.cancel();
    });

    test('starts an operation posted meanwhile paused', () async {
      final token = await sse.reserve(handler);
      final reader = await connected(token);
      await Future<void>.delayed(Duration.zero);
      reader.pause();
      await handler.handle(sse.operation(token, 'subscription { count }'));
      expect(await resolvedAfterSettling(), lessThanOrEqualTo(2));
      await reader.cancel();
    });
  });

  group('an operation', () {
    test('keeps running when the cancel signal of its POST fires', () async {
      final token = await sse.reserve(handler);
      final reader = await connected(token);
      final signal = CancelSignal();
      final response = await handler.handle(
        sse.http.post(
          {
            'query': 'subscription { count }',
            'extensions': {'operationId': 'op'},
          },
          headers: {
            ...HttpFixture.modernClient,
            SseFixture.tokenHeader: token,
          },
          cancelSignal: signal,
        ),
      );
      await reader.waitFor(1);
      signal.cancel();
      final resolved = counting.resolved;
      await Future<void>.delayed(_settle);
      expect(response.status, 202);
      expect(counting.resolved, greaterThan(resolved));
      await reader.cancel();
    });
  });

  group('a token', () {
    test('with a bad escape is no token and no server fault', () async {
      final response = await handler.handle(
        HttpRequestData(
          method: 'GET',
          uri: Uri.parse('/graphql?token=%ff'),
          headers: {...HttpFixture.preflight, ...SseFixture.eventStreamClient},
        ),
      );
      expect(response.status, lessThan(500));
      expect(await sse.http.code(response), isNotNull);
    });
  });

  group('StreamOperation', () {
    late StreamController<JsonValue> spy;
    late bool isReleased;
    late SingleConnection connection;

    setUp(() {
      isReleased = false;
      spy = StreamController<JsonValue>(onCancel: () => isReleased = true);
      addTearDown(() => spy.close().ignore());
      connection = SingleConnection(
        2,
        onClosed: () {},
        onListening: () {},
      );
    });

    test('cancelled before its results arrive releases them at once', () {
      final operation = connection.admit('a')..cancel();
      operation.attach(spy.stream);
      expect(isReleased, isTrue);
    });

    test('cancelled while its results wait releases them', () {
      final operation = connection.admit('a')..attach(spy.stream);
      expect(isReleased, isFalse);
      operation.cancel();
      expect(isReleased, isTrue);
    });
  });
}
