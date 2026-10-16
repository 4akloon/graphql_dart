import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

/// A random whose every draw is one half, so the full-jitter delays are half
/// of each ceiling: 150 ms, 300 ms, 600 ms with the default backoff.
final class HalfRandom implements Random {
  const HalfRandom();

  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => max ~/ 2;
}

void main() {
  final hello = JsonObject({'hello': const JsonString('world')});
  const networkFailure = NetworkFailure(FormatException('down'));
  final query = LinkRequest.of(const HelloQuery());

  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  RetryLink retryLink({RetryPolicy policy = const RetryPolicy()}) =>
      RetryLink(policy: policy, random: const HalfRandom());

  /// Runs [link] on [request] and collects what it emits.
  ({List<LinkResult> results, bool Function() isDone}) listenTo(
    Link link,
    LinkRequest request,
  ) {
    final results = <LinkResult>[];
    var isDone = false;
    link
        .request(request, unterminated)
        .listen(results.add, onDone: () => isDone = true);
    return (results: results, isDone: () => isDone);
  }

  group('RetryLink', () {
    test('forwards the request again after the backoff delay', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addData(hello);
        final link = Link.from([retryLink(), mock]);
        final results = <LinkResult>[];
        link.request(query, unterminated).listen(results.add);
        async.flushMicrotasks();
        expect(mock.requests, hasLength(1));
        async.elapse(const Duration(milliseconds: 149));
        expect(mock.requests, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(mock.requests, hasLength(2));
        expect(results.single, isA<LinkPayload>());
      });
    });

    test('waits for the next ceiling before each further retry', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addFailure(networkFailure)
          ..addData(hello);
        Link.from([
          retryLink(),
          mock,
        ]).request(query, unterminated).listen((_) {});
        async.elapse(const Duration(milliseconds: 150));
        expect(mock.requests, hasLength(2));
        async.elapse(const Duration(milliseconds: 299));
        expect(mock.requests, hasLength(2));
        async.elapse(const Duration(milliseconds: 1));
        expect(mock.requests, hasLength(3));
      });
    });

    test('delivers the last failure when the attempts run out', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addFailure(networkFailure)
          ..addFailure(networkFailure)
          ..addData(hello);
        final run = listenTo(Link.from([retryLink(), mock]), query);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(3));
        expect(run.results.single, isA<LinkFailure>());
        expect(run.isDone(), isTrue);
      });
    });

    test('a maxAttempts of 1 never retries', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addData(hello);
        final results = <LinkResult>[];
        Link.from([
          retryLink(policy: const RetryPolicy(maxAttempts: 1)),
          mock,
        ]).request(query, unterminated).listen(results.add);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(1));
        expect(results.single, isA<LinkFailure>());
      });
    });

    test('does not retry a failure outside the default set', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(HttpStatusFailure(400))
          ..addData(hello);
        final results = <LinkResult>[];
        Link.from([
          retryLink(),
          mock,
        ]).request(query, unterminated).listen(results.add);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(1));
        expect(results.single, isA<LinkFailure>());
      });
    });

    for (final status in [408, 429, 500, 502, 503, 504]) {
      test('retries HTTP status $status by default', () {
        expect(
          const RetryPolicy().isRetryable(HttpStatusFailure(status)),
          true,
        );
      });
    }

    test('retries a timeout by default', () {
      expect(
        const RetryPolicy().isRetryable(
          const RequestTimedOut(Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('never retries a cancellation by default', () {
      expect(const RetryPolicy().isRetryable(const RequestCancelled()), false);
    });

    test('does not retry a GraphQL error payload', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addErrors([GraphQLError('boom')])
          ..addData(hello);
        final results = <LinkResult>[];
        Link.from([
          retryLink(),
          mock,
        ]).request(query, unterminated).listen(results.add);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(1));
        expect(results.single, isA<LinkPayload>());
      });
    });

    test('does not retry a mutation without Idempotent', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addData(hello);
        final results = <LinkResult>[];
        Link.from([retryLink(), mock])
            .request(LinkRequest.of(const RenameMutation('a')), unterminated)
            .listen(results.add);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(1));
        expect(results.single, isA<LinkFailure>());
      });
    });

    test('retries a mutation whose context has Idempotent', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addData(hello);
        final results = <LinkResult>[];
        Link.from([retryLink(), mock])
            .request(
              LinkRequest.of(
                const RenameMutation('a'),
                context: LinkContext([const Idempotent()]),
              ),
              unterminated,
            )
            .listen(results.add);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(2));
        expect(results.single, isA<LinkPayload>());
      });
    });

    test('passes a subscription through unchanged', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addData(hello);
        final results = <LinkResult>[];
        Link.from([retryLink(), mock])
            .request(LinkRequest.of(const TicksSubscription()), unterminated)
            .listen(results.add);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(1));
        expect(results.single, isA<LinkFailure>());
      });
    });

    test('retryIf replaces the default decision', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(HttpStatusFailure(400))
          ..addData(hello);
        final results = <LinkResult>[];
        Link.from([
          retryLink(
            policy: RetryPolicy(
              retryIf: (failure) =>
                  failure is HttpStatusFailure && failure.statusCode == 400,
            ),
          ),
          mock,
        ]).request(query, unterminated).listen(results.add);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(2));
        expect(results.single, isA<LinkPayload>());
      });
    });

    test('retryIf can refuse a failure the default would retry', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addData(hello);
        final results = <LinkResult>[];
        Link.from([
          retryLink(policy: RetryPolicy(retryIf: (failure) => false)),
          mock,
        ]).request(query, unterminated).listen(results.add);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(1));
      });
    });

    test('cancelling during the wait leaves no timer and no request', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addData(hello);
        final subscription = Link.from([
          retryLink(),
          mock,
        ]).request(query, unterminated).listen((_) {});
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 1);
        subscription.cancel();
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 0);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(1));
      });
    });

    test('cancelling while an attempt runs cancels the forwarded stream', () {
      fakeAsync((async) {
        var isUpstreamCancelled = false;
        final upstream = StreamController<LinkResult>(
          onCancel: () => isUpstreamCancelled = true,
        );
        final mock = MockLink()..addStream(upstream.stream);
        final subscription = Link.from([
          retryLink(),
          mock,
        ]).request(query, unterminated).listen((_) {});
        async.flushMicrotasks();
        subscription.cancel();
        async.flushMicrotasks();
        expect(isUpstreamCancelled, isTrue);
        upstream.close();
      });
    });

    test('a throwing retryIf ends the stream with that error', () async {
      final mock = MockLink()..addFailure(networkFailure);
      final link = Link.from([
        retryLink(
          policy: RetryPolicy(retryIf: (failure) => throw StateError('bad')),
        ),
        mock,
      ]);
      await expectLater(
        link.request(query, unterminated),
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
    });

    test('an Exception from the stream below is judged as a failure', () {
      fakeAsync((async) {
        final mock = MockLink()
          ..addStream(Stream.error(const FormatException('down')))
          ..addData(hello);
        final run = listenTo(Link.from([retryLink(), mock]), query);
        async.elapse(const Duration(minutes: 1));
        expect(mock.requests, hasLength(2));
        expect(run.results.single, isA<LinkPayload>());
      });
    });

    test('a request with UploadFiles forwards the same files twice', () {
      fakeAsync((async) {
        final files = UploadFiles([
          UploadFile.fromBytes([1, 2, 3], filename: 'a.bin'),
        ]);
        final mock = MockLink()
          ..addFailure(networkFailure)
          ..addData(hello);
        listenTo(
          Link.from([retryLink(), mock]),
          query.withContext(LinkContext([files])),
        );
        async.elapse(const Duration(minutes: 1));
        expect(
          mock.requests.map((request) => request.context.entry<UploadFiles>()),
          [same(files), same(files)],
        );
      });
    });

    test('a maxAttempts below 1 is an ArgumentError', () {
      expect(
        () => RetryLink(policy: const RetryPolicy(maxAttempts: 0)),
        throwsArgumentError,
      );
    });
  });
}
