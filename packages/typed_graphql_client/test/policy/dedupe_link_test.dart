import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  final hello = LinkPayload(
    ExecutionResult(JsonObject({'hello': const JsonString('world')})),
  );
  final query = LinkRequest.of(const HelloQuery());

  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  /// A link chain over a [MockLink] whose first answer is [controller]'s.
  ({Link link, MockLink mock}) chainOver(StreamController<LinkResult> source) {
    final mock = MockLink()..addStream(source.stream);
    return (link: Link.from([DedupeLink(), mock]), mock: mock);
  }

  group('DedupeLink', () {
    test('two identical queries in flight forward one request', () async {
      final source = StreamController<LinkResult>();
      final (:link, :mock) = chainOver(source);
      link.request(query, unterminated).listen((_) {});
      link.request(query, unterminated).listen((_) {});
      await pumpEventQueue();
      expect(mock.requests, hasLength(1));
      await source.close();
    });

    test('every caller gets the shared result and ends', () async {
      final source = StreamController<LinkResult>();
      final (:link, :mock) = chainOver(source);
      final first = link.request(query, unterminated).toList();
      final second = link.request(query, unterminated).toList();
      await pumpEventQueue();
      source.add(hello);
      await source.close();
      expect(await first, [hello]);
      expect(await second, [hello]);
    });

    test('different variables are not shared', () async {
      final mock = MockLink()
        ..addData(JsonObject(const {}))
        ..addData(JsonObject(const {}));
      final link = Link.from([DedupeLink(), mock]);
      final first = link.request(
        LinkRequest.of(const GreetQuery('a')),
        unterminated,
      );
      final second = link.request(
        LinkRequest.of(const GreetQuery('b')),
        unterminated,
      );
      await Future.wait([first.drain<void>(), second.drain<void>()]);
      expect(mock.requests, hasLength(2));
    });

    test('different headers are not shared', () async {
      final mock = MockLink()
        ..addData(JsonObject(const {}))
        ..addData(JsonObject(const {}));
      final link = Link.from([DedupeLink(), mock]);
      LinkRequest withToken(String token) => query.withContext(
        LinkContext([
          RequestHeaders({'authorization': token}),
        ]),
      );
      await Future.wait([
        link.request(withToken('a'), unterminated).drain<void>(),
        link.request(withToken('b'), unterminated).drain<void>(),
      ]);
      expect(mock.requests, hasLength(2));
    });

    test('equal headers written with other case are shared', () async {
      final source = StreamController<LinkResult>();
      final (:link, :mock) = chainOver(source);
      link
          .request(
            query.withContext(
              LinkContext([
                RequestHeaders({'X-A': '1'}),
              ]),
            ),
            unterminated,
          )
          .listen((_) {});
      link
          .request(
            query.withContext(
              LinkContext([
                RequestHeaders({'x-a': '1'}),
              ]),
            ),
            unterminated,
          )
          .listen((_) {});
      await pumpEventQueue();
      expect(mock.requests, hasLength(1));
      await source.close();
    });

    test('mutations are not shared', () async {
      final mock = MockLink()
        ..addData(JsonObject(const {}))
        ..addData(JsonObject(const {}));
      final link = Link.from([DedupeLink(), mock]);
      final mutation = LinkRequest.of(const RenameMutation('a'));
      await Future.wait([
        link.request(mutation, unterminated).drain<void>(),
        link.request(mutation, unterminated).drain<void>(),
      ]);
      expect(mock.requests, hasLength(2));
    });

    test('a request with UploadFiles is not shared', () async {
      final mock = MockLink()
        ..addData(JsonObject(const {}))
        ..addData(JsonObject(const {}));
      final link = Link.from([DedupeLink(), mock]);
      final upload = query.withContext(LinkContext([UploadFiles(const [])]));
      await Future.wait([
        link.request(upload, unterminated).drain<void>(),
        link.request(upload, unterminated).drain<void>(),
      ]);
      expect(mock.requests, hasLength(2));
    });

    test('a caller that cancels leaves the others their result', () async {
      final source = StreamController<LinkResult>();
      final (:link, :mock) = chainOver(source);
      final received = <LinkResult>[];
      final leaving = link.request(query, unterminated).listen((_) {});
      link.request(query, unterminated).listen(received.add);
      await pumpEventQueue();
      await leaving.cancel();
      source.add(hello);
      await source.close();
      await pumpEventQueue();
      expect(received, [hello]);
    });

    test('the forwarded request is cancelled with the last caller', () async {
      var isUpstreamCancelled = false;
      final source = StreamController<LinkResult>(
        onCancel: () => isUpstreamCancelled = true,
      );
      final (:link, :mock) = chainOver(source);
      final first = link.request(query, unterminated).listen((_) {});
      final second = link.request(query, unterminated).listen((_) {});
      await pumpEventQueue();
      await first.cancel();
      expect(isUpstreamCancelled, isFalse);
      await second.cancel();
      expect(isUpstreamCancelled, isTrue);
      await source.close();
    });

    test('every caller gets a stream error of the source', () async {
      final source = StreamController<LinkResult>();
      final (:link, :mock) = chainOver(source);
      final first = link.request(query, unterminated);
      final second = link.request(query, unterminated);
      final outcomes = Future.wait([
        expectLater(first, emitsError(isA<StateError>())),
        expectLater(second, emitsError(isA<StateError>())),
      ]);
      await pumpEventQueue();
      source.addError(StateError('boom'));
      await outcomes;
      await source.close();
    });

    test('variables in another key order are shared', () async {
      final source = StreamController<LinkResult>();
      final (:link, :mock) = chainOver(source);
      LinkRequest withVariables(Map<String, JsonValue> variables) =>
          LinkRequest(
            document: query.document,
            variables: JsonObject(variables),
          );
      link
          .request(
            withVariables({'a': JsonNumber(1), 'b': JsonNumber(2)}),
            unterminated,
          )
          .listen((_) {});
      link
          .request(
            withVariables({'b': JsonNumber(2), 'a': JsonNumber(1)}),
            unterminated,
          )
          .listen((_) {});
      await pumpEventQueue();
      expect(mock.requests, hasLength(1));
      await source.close();
    });

    test('a caller that listens late joins the request in flight', () async {
      final source = StreamController<LinkResult>();
      final (:link, :mock) = chainOver(source);
      link.request(query, unterminated).listen((_) {});
      final late = link.request(query, unterminated);
      await pumpEventQueue();
      final received = late.toList();
      await pumpEventQueue();
      source.add(hello);
      await source.close();
      expect(await received, [hello]);
      expect(mock.requests, hasLength(1));
    });

    test('a failure as the first result ends the sharing', () async {
      final source = StreamController<LinkResult>();
      final mock = MockLink()
        ..addStream(source.stream)
        ..addData(JsonObject(const {}));
      final link = Link.from([DedupeLink(), mock]);
      link.request(query, unterminated).listen((_) {});
      await pumpEventQueue();
      source.add(const LinkFailure(NetworkFailure(FormatException('down'))));
      await pumpEventQueue();
      await link.request(query, unterminated).drain<void>();
      expect(mock.requests, hasLength(2));
      await source.close();
    });

    test('a source that ends while it is listened to ends the caller', () {
      final link = DedupeLink();
      final results = link.request(
        query,
        (request) => Stream<LinkResult>.multi((controller) {
          controller.add(hello);
          controller.close();
        }),
      );
      expect(results.toList(), completion([hello]));
    });

    test('a forward that throws is the error of the caller', () async {
      final link = DedupeLink();
      await expectLater(
        link.request(query, (request) => throw StateError('boom')),
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
    });

    test('a forward that throws leaves nothing in flight', () async {
      final link = DedupeLink();
      await link
          .request(query, (request) => throw StateError('boom'))
          .handleError((Object error) {})
          .drain<void>();
      var forwardCount = 0;
      await link.request(query, (request) {
        forwardCount++;
        return Stream.value(hello);
      }).drain<void>();
      expect(forwardCount, 1);
    });

    test('a query sent after the result is forwarded again', () async {
      final mock = MockLink()
        ..addData(JsonObject(const {}))
        ..addData(JsonObject(const {}));
      final link = Link.from([DedupeLink(), mock]);
      await link.request(query, unterminated).drain<void>();
      await link.request(query, unterminated).drain<void>();
      expect(mock.requests, hasLength(2));
    });

    test('a query sent after everyone cancelled is forwarded again', () async {
      final source = StreamController<LinkResult>();
      final mock = MockLink()
        ..addStream(source.stream)
        ..addData(JsonObject(const {}));
      final link = Link.from([DedupeLink(), mock]);
      await link.request(query, unterminated).listen((_) {}).cancel();
      await link.request(query, unterminated).drain<void>();
      expect(mock.requests, hasLength(2));
      await source.close();
    });
  });
}
