import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  final hello = JsonObject({'hello': const JsonString('world')});
  final query = LinkRequest.of(const HelloQuery());
  final unauthorized = HttpStatusFailure(401);

  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  String? authorizationOf(LinkRequest request) =>
      request.context.entry<RequestHeaders>()?.values['authorization'];

  Future<List<LinkResult>> run(AuthLink auth, MockLink mock) =>
      Link.from([auth, mock]).request(query, unterminated).toList();

  // A LinkResult has no value equality; its failure or payload may.
  Object? failureOf(List<LinkResult> results) => switch (results) {
    [LinkFailure(:final failure)] => failure,
    _ => null,
  };

  group('AuthLink', () {
    test('adds the bearer header', () async {
      final mock = MockLink()..addData(hello);
      await run(AuthLink(token: () => 'abc'), mock);
      expect(authorizationOf(mock.requests.single), 'Bearer abc');
    });

    test('waits for an asynchronous token', () async {
      final mock = MockLink()..addData(hello);
      await run(AuthLink(token: () async => 'abc'), mock);
      expect(authorizationOf(mock.requests.single), 'Bearer abc');
    });

    test('keeps the headers the request already has', () async {
      final mock = MockLink()..addData(hello);
      final link = Link.from([AuthLink(token: () => 'abc'), mock]);
      await link
          .request(
            query.withContext(
              LinkContext([
                RequestHeaders({'X-Trace': '1'}),
              ]),
            ),
            unterminated,
          )
          .drain<void>();
      final headers = mock.requests.single.context.entry<RequestHeaders>();
      expect(headers?.values, {'x-trace': '1', 'authorization': 'Bearer abc'});
    });

    test('uses the header name and the scheme it is given', () async {
      final mock = MockLink()..addData(hello);
      await run(
        AuthLink(token: () => 'abc', headerName: 'X-Token', scheme: 'Token'),
        mock,
      );
      final headers = mock.requests.single.context.entry<RequestHeaders>();
      expect(headers?.values, {'x-token': 'Token abc'});
    });

    test('an empty scheme sends the bare token', () async {
      final mock = MockLink()..addData(hello);
      await run(AuthLink(token: () => 'abc', scheme: ''), mock);
      expect(authorizationOf(mock.requests.single), 'abc');
    });

    test('a null token adds no header', () async {
      final mock = MockLink()..addData(hello);
      await run(AuthLink(token: () => null), mock);
      expect(mock.requests.single.context.entry<RequestHeaders>(), isNull);
    });

    test('a 401 refreshes the token and sends the request again', () async {
      var current = 'old';
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addData(hello);
      final results = await run(
        AuthLink(
          token: () => current,
          refresh: () async => current = 'new',
        ),
        mock,
      );
      expect(
        mock.requests.map(authorizationOf),
        ['Bearer old', 'Bearer new'],
      );
      expect(results.single, isA<LinkPayload>());
    });

    test('two requests that get a 401 together refresh once', () async {
      var current = 'old';
      var refreshCount = 0;
      final refreshed = Completer<String?>();
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addFailure(unauthorized)
        ..addData(hello)
        ..addData(hello);
      final link = Link.from([
        AuthLink(
          token: () => current,
          refresh: () {
            refreshCount++;
            return refreshed.future;
          },
        ),
        mock,
      ]);
      final first = link.request(query, unterminated).toList();
      final second = link.request(query, unterminated).toList();
      await pumpEventQueue();
      current = 'new';
      refreshed.complete('new');
      await Future.wait([first, second]);
      expect(refreshCount, 1);
      expect(mock.requests.map(authorizationOf), [
        'Bearer old',
        'Bearer old',
        'Bearer new',
        'Bearer new',
      ]);
    });

    test('a token that changed meanwhile is used without a refresh', () async {
      final tokens = ['old', 'new'];
      var refreshCount = 0;
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addData(hello);
      await run(
        AuthLink(
          token: () => tokens.removeAt(0),
          refresh: () async {
            refreshCount++;
            return 'refreshed';
          },
        ),
        mock,
      );
      expect(refreshCount, 0);
      expect(authorizationOf(mock.requests.last), 'Bearer new');
    });

    test('without refresh the 401 is delivered', () async {
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addData(hello);
      final results = await run(AuthLink(token: () => 'old'), mock);
      expect(failureOf(results), same(unauthorized));
      expect(mock.requests, hasLength(1));
    });

    test('a refresh that gives null delivers the 401', () async {
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addData(hello);
      final results = await run(
        AuthLink(token: () => 'old', refresh: () async => null),
        mock,
      );
      expect(failureOf(results), same(unauthorized));
      expect(mock.requests, hasLength(1));
    });

    test('a second 401 is delivered, not retried', () async {
      final second = HttpStatusFailure(401);
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addFailure(second)
        ..addData(hello);
      final results = await run(
        AuthLink(token: () => 'old', refresh: () async => 'new'),
        mock,
      );
      expect(failureOf(results), same(second));
      expect(mock.requests, hasLength(2));
    });

    test('another failure is delivered without a refresh', () async {
      var refreshCount = 0;
      final mock = MockLink()..addFailure(HttpStatusFailure(500));
      await run(
        AuthLink(
          token: () => 'old',
          refresh: () async {
            refreshCount++;
            return 'new';
          },
        ),
        mock,
      );
      expect(refreshCount, 0);
    });

    test('a payload with HTTP status 401 counts as unauthorized', () async {
      final mock = MockLink()
        ..add(
          LinkPayload(
            RequestErrorResult(errors: [GraphQLError('no')]),
            context: LinkContext([HttpResponseInfo(401)]),
          ),
        )
        ..addData(hello);
      await run(
        AuthLink(token: () => 'old', refresh: () async => 'new'),
        mock,
      );
      expect(mock.requests, hasLength(2));
    });

    test('isUnauthorized replaces the default test', () async {
      final mock = MockLink()
        ..addFailure(HttpStatusFailure(403))
        ..addData(hello);
      await run(
        AuthLink(
          token: () => 'old',
          refresh: () async => 'new',
          isUnauthorized: (result) => switch (result) {
            LinkFailure(failure: HttpStatusFailure(statusCode: 403)) => true,
            _ => false,
          },
        ),
        mock,
      );
      expect(authorizationOf(mock.requests.last), 'Bearer new');
    });

    test('a token callback that throws is an AuthenticationFailure', () async {
      final mock = MockLink()..addData(hello);
      final results = await run(
        AuthLink(token: () => throw const FormatException('locked')),
        mock,
      );
      expect(failureOf(results), isA<AuthenticationFailure>());
      expect(mock.requests, isEmpty);
    });

    test('a refresh that throws is an AuthenticationFailure', () async {
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addData(hello);
      final results = await run(
        AuthLink(
          token: () => 'old',
          refresh: () async => throw const FormatException('expired'),
        ),
        mock,
      );
      expect(failureOf(results), isA<AuthenticationFailure>());
      expect(mock.requests, hasLength(1));
    });

    test('a request that read its token slowly reuses the refresh', () async {
      final gate = Completer<String?>();
      final reads = <FutureOr<String?>>['old', 'old', 'old', gate.future];
      final refreshed = Completer<String?>();
      var refreshCount = 0;
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addFailure(unauthorized)
        ..addData(hello)
        ..addData(hello);
      final link = Link.from([
        AuthLink(
          token: () => reads.removeAt(0),
          refresh: () {
            refreshCount++;
            return refreshed.future;
          },
        ),
        mock,
      ]);
      final first = link.request(query, unterminated).toList();
      final second = link.request(query, unterminated).toList();
      await pumpEventQueue();
      refreshed.complete('new');
      await pumpEventQueue();
      gate.complete('old');
      await Future.wait([first, second]);
      expect(refreshCount, 1);
      expect(mock.requests.map(authorizationOf).skip(2), [
        'Bearer new',
        'Bearer new',
      ]);
    });

    test('a token callback that throws an Error ends the stream', () async {
      final mock = MockLink()..addData(hello);
      await expectLater(
        Link.from([
          AuthLink(token: () => throw StateError('bug')),
          mock,
        ]).request(query, unterminated),
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
      expect(mock.requests, isEmpty);
    });

    test('a refresh that throws an Error ends the stream', () async {
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addData(hello);
      await expectLater(
        Link.from([
          AuthLink(
            token: () => 'old',
            refresh: () async => throw StateError('bug'),
          ),
          mock,
        ]).request(query, unterminated),
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
    });

    test('an isUnauthorized that throws ends the stream', () async {
      final mock = MockLink()..addFailure(unauthorized);
      await expectLater(
        Link.from([
          AuthLink(
            token: () => 'old',
            refresh: () async => 'new',
            isUnauthorized: (result) => throw StateError('bug'),
          ),
          mock,
        ]).request(query, unterminated),
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
    });

    test('a stream error of the source passes through', () async {
      final mock = MockLink()..addStream(Stream.error(StateError('boom')));
      await expectLater(
        Link.from([
          AuthLink(token: () => 'old', refresh: () async => 'new'),
          mock,
        ]).request(query, unterminated),
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
    });

    test('the next 401 refreshes again after a refresh failed', () async {
      var refreshCount = 0;
      final link = AuthLink(
        token: () => 'old',
        refresh: () async {
          refreshCount++;
          if (refreshCount == 1) throw const FormatException('expired');
          return 'new';
        },
      );
      await run(link, MockLink()..addFailure(unauthorized));
      final mock = MockLink()
        ..addFailure(unauthorized)
        ..addData(hello);
      await run(link, mock);
      expect(refreshCount, 2);
      expect(authorizationOf(mock.requests.last), 'Bearer new');
    });

    test(
      'cancelling while the token is refreshed sends nothing more',
      () async {
        final refreshed = Completer<String?>();
        final mock = MockLink()
          ..addFailure(unauthorized)
          ..addData(hello);
        final subscription = Link.from([
          AuthLink(token: () => 'old', refresh: () => refreshed.future),
          mock,
        ]).request(query, unterminated).listen((_) {});
        await pumpEventQueue();
        await subscription.cancel();
        refreshed.complete('new');
        await pumpEventQueue();
        expect(mock.requests, hasLength(1));
      },
    );

    test('cancelling cancels the running attempt', () async {
      var isUpstreamCancelled = false;
      final source = StreamController<LinkResult>(
        onCancel: () => isUpstreamCancelled = true,
      );
      final mock = MockLink()..addStream(source.stream);
      final subscription = Link.from([
        AuthLink(token: () => 'old'),
        mock,
      ]).request(query, unterminated).listen((_) {});
      await pumpEventQueue();
      await subscription.cancel();
      expect(isUpstreamCancelled, isTrue);
      await source.close();
    });
  });
}
