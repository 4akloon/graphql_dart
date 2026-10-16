import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  final hello = JsonObject({'hello': const JsonString('world')});
  final query = LinkRequest.of(const HelloQuery());
  final hash = HelloQuery.operationDocument.sha256;

  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  GraphQLError errorWith({String message = 'x', String? code}) => GraphQLError(
    message,
    extensions: code == null ? null : JsonObject({'code': JsonString(code)}),
  );

  Future<List<LinkResult>> run(
    PersistedQueryLink persisted,
    MockLink mock,
    LinkRequest request,
  ) => Link.from([
    persisted,
    mock,
  ]).request(request, unterminated).toList();

  // A LinkPayload has no value equality; its payload has.
  List<ResponsePayload> payloadsOf(List<LinkResult> results) => [
    for (final result in results)
      if (result is LinkPayload) result.payload,
  ];

  JsonValue? persistedQueryOf(LinkRequest request) =>
      request.extensions?['persistedQuery'];

  group('PersistedQueryLink', () {
    test('first sends the hash alone', () async {
      final mock = MockLink()..addData(hello);
      await run(PersistedQueryLink(), mock, query);
      final sent = mock.requests.single;
      expect(sent.body.query, isNull);
      expect(
        persistedQueryOf(sent),
        JsonObject({
          'version': JsonNumber(1),
          'sha256Hash': JsonString(hash),
        }),
      );
    });

    test('delivers an answer to the hash alone as it is', () async {
      final mock = MockLink()..addData(hello);
      final results = await run(PersistedQueryLink(), mock, query);
      expect(payloadsOf(results), [ExecutionResult(hello)]);
      expect(mock.requests, hasLength(1));
    });

    test('keeps the extensions the request already has', () async {
      final mock = MockLink()..addData(hello);
      await run(
        PersistedQueryLink(),
        mock,
        query.withExtensions(JsonObject({'trace': const JsonBool(true)})),
      );
      expect(
        mock.requests.single.extensions?['trace'],
        const JsonBool(true),
      );
      expect(persistedQueryOf(mock.requests.single), isNotNull);
    });

    test(
      'a miss sends the text and the hash and delivers that answer',
      () async {
        final mock = MockLink()
          ..addErrors([errorWith(message: 'PersistedQueryNotFound')])
          ..addData(hello);
        final results = await run(PersistedQueryLink(), mock, query);
        expect(payloadsOf(results), [ExecutionResult(hello)]);
        final second = mock.requests.last;
        expect(second.body.query, HelloQuery.operationDocument.text);
        expect(persistedQueryOf(second), isNotNull);
      },
    );

    for (final code in ['GQL410', 'PERSISTED_QUERY_NOT_FOUND']) {
      test('the code $code is a miss', () async {
        final mock = MockLink()
          ..addErrors([errorWith(code: code)])
          ..addData(hello);
        await run(PersistedQueryLink(), mock, query);
        expect(mock.requests, hasLength(2));
        expect(mock.requests.last.body.query, isNotNull);
      });
    }

    test('a second miss after the text was sent is delivered', () async {
      final mock = MockLink()
        ..addErrors([errorWith(message: 'PersistedQueryNotFound')])
        ..addErrors([errorWith(message: 'PersistedQueryNotFound')])
        ..addData(hello);
      final results = await run(PersistedQueryLink(), mock, query);
      expect(mock.requests, hasLength(2));
      expect(mock.pendingAnswerCount, 1);
      expect(payloadsOf(results), [
        RequestErrorResult(
          errors: [errorWith(message: 'PersistedQueryNotFound')],
        ),
      ]);
    });

    test('a stream error of the source passes through', () async {
      final mock = MockLink()..addStream(Stream.error(StateError('boom')));
      await expectLater(
        Link.from([PersistedQueryLink(), mock]).request(query, unterminated),
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
    });

    test('not supported sends the text without the hash', () async {
      final mock = MockLink()
        ..addErrors([errorWith(message: 'PersistedQueryNotSupported')])
        ..addData(hello);
      final results = await run(PersistedQueryLink(), mock, query);
      expect(payloadsOf(results), [ExecutionResult(hello)]);
      final second = mock.requests.last;
      expect(second.body.query, HelloQuery.operationDocument.text);
      expect(persistedQueryOf(second), isNull);
    });

    for (final code in ['GQL412', 'PERSISTED_QUERY_NOT_SUPPORTED']) {
      test('the code $code is not supported', () async {
        final mock = MockLink()
          ..addErrors([errorWith(code: code)])
          ..addData(hello);
        await run(PersistedQueryLink(), mock, query);
        expect(persistedQueryOf(mock.requests.last), isNull);
        expect(mock.requests.last.body.query, isNotNull);
      });
    }

    test('after not supported the link sends text only', () async {
      final mock = MockLink()
        ..addErrors([errorWith(code: 'GQL412')])
        ..addData(hello)
        ..addData(hello);
      final persisted = PersistedQueryLink();
      await run(persisted, mock, query);
      await run(persisted, mock, query);
      expect(mock.requests, hasLength(3));
      expect(mock.requests.last.body.query, isNotNull);
      expect(persistedQueryOf(mock.requests.last), isNull);
    });

    test('after a miss the next request tries the hash again', () async {
      final mock = MockLink()
        ..addErrors([errorWith(code: 'GQL410')])
        ..addData(hello)
        ..addData(hello);
      final persisted = PersistedQueryLink();
      await run(persisted, mock, query);
      await run(persisted, mock, query);
      expect(mock.requests.last.body.query, isNull);
    });

    test('another error is delivered without a second request', () async {
      final mock = MockLink()..addErrors([errorWith(code: 'OTHER')]);
      final results = await run(PersistedQueryLink(), mock, query);
      expect(results, hasLength(1));
      expect(mock.requests, hasLength(1));
    });

    test('a failure is delivered without a second request', () async {
      final mock = MockLink()
        ..addFailure(const NetworkFailure(FormatException('down')));
      final results = await run(PersistedQueryLink(), mock, query);
      expect(results.single, isA<LinkFailure>());
      expect(mock.requests, hasLength(1));
    });

    test('a mutation is sent as a hash first', () async {
      final mock = MockLink()..addData(hello);
      await run(
        PersistedQueryLink(),
        mock,
        LinkRequest.of(const RenameMutation('a')),
      );
      expect(mock.requests.single.body.query, isNull);
    });

    test('trusted mode sends the hash alone and never the text', () async {
      final mock = MockLink()
        ..addErrors([errorWith(code: 'GQL410')])
        ..addErrors([errorWith(code: 'GQL412')]);
      final persisted = PersistedQueryLink(isAutomatic: false);
      final first = await run(persisted, mock, query);
      await run(persisted, mock, query);
      expect(first, hasLength(1));
      expect(mock.requests.map((request) => request.body.query), [null, null]);
    });

    test('a subscription is forwarded untouched', () async {
      final mock = MockLink()..addData(hello);
      final subscription = LinkRequest.of(const TicksSubscription());
      await run(PersistedQueryLink(), mock, subscription);
      expect(mock.requests.single.body.query, isNotNull);
      expect(mock.requests.single.extensions, isNull);
    });

    test('a request with UploadFiles is forwarded untouched', () async {
      final mock = MockLink()..addData(hello);
      await run(
        PersistedQueryLink(),
        mock,
        query.withContext(LinkContext([UploadFiles(const [])])),
      );
      expect(mock.requests.single.body.query, isNotNull);
      expect(mock.requests.single.extensions, isNull);
    });

    test('cancelling cancels the running attempt', () async {
      var isUpstreamCancelled = false;
      final source = StreamController<LinkResult>(
        onCancel: () => isUpstreamCancelled = true,
      );
      final mock = MockLink()..addStream(source.stream);
      final subscription = Link.from([
        PersistedQueryLink(),
        mock,
      ]).request(query, unterminated).listen((_) {});
      await pumpEventQueue();
      await subscription.cancel();
      expect(isUpstreamCancelled, isTrue);
      await source.close();
    });

    test('cancelling during the second attempt cancels it', () async {
      var isUpstreamCancelled = false;
      final source = StreamController<LinkResult>(
        onCancel: () => isUpstreamCancelled = true,
      );
      final mock = MockLink()
        ..addErrors([errorWith(code: 'GQL410')])
        ..addStream(source.stream);
      final subscription = Link.from([
        PersistedQueryLink(),
        mock,
      ]).request(query, unterminated).listen((_) {});
      await pumpEventQueue();
      expect(mock.requests, hasLength(2));
      await subscription.cancel();
      expect(isUpstreamCancelled, isTrue);
      await source.close();
    });
  });
}
