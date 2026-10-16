import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'client_cancellation_test.dart' show OpenLink;

/// Answers each request with a stream that delivers [result] and ends
/// inside `listen`, before it returns.
final class SynchronousLink extends Link {
  SynchronousLink(this.result);

  final LinkResult result;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) =>
      Stream<LinkResult>.multi((controller) {
        controller
          ..add(result)
          ..close();
      });
}

void main() {
  LinkResult ticks(int value) =>
      LinkPayload(ExecutionResult(JsonObject({'ticks': JsonNumber(value)})));

  group('a subscribe stream', () {
    test('pauses and resumes the link stream with its subscription', () async {
      final link = OpenLink();
      final events = <GraphQLResponse<int>>[];
      final subscription = GraphQLClient(
        link: link,
      ).subscribe(const TicksSubscription()).listen(events.add);
      await Future<void>.delayed(Duration.zero);
      final source = link.controllers.single;
      subscription.pause();
      expect(source.isPaused, isTrue);
      source.add(ticks(1));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      subscription.resume();
      await Future<void>.delayed(Duration.zero);
      expect(source.isPaused, isFalse);
      expect(events, hasLength(1));
      await subscription.cancel();
    });

    test('a link stream error that is not an Exception is an error event', () {
      final link = MockLink()
        ..addStream(Stream<LinkResult>.error(StateError('bug')));
      expect(
        GraphQLClient(link: link).subscribe(const TicksSubscription()),
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
    });

    test('a link stream Exception is a network failure', () async {
      final link = MockLink()
        ..addStream(Stream<LinkResult>.error(const FormatException('x')));
      final responses = await GraphQLClient(
        link: link,
      ).subscribe(const TicksSubscription()).toList();
      expect(
        responses.single,
        isA<GraphQLTransportFailure<int>>().having(
          (failure) => failure.failure,
          'failure',
          isA<NetworkFailure>(),
        ),
      );
    });

    test('with a cancelled token gives the failure and ends', () async {
      final link = MockLink();
      final responses = await GraphQLClient(link: link)
          .subscribe(
            const TicksSubscription(),
            cancelToken: CancelToken()..cancel('gone'),
          )
          .toList();
      expect(responses, hasLength(1));
      expect(
        responses.single,
        isA<GraphQLTransportFailure<int>>().having(
          (failure) => failure.failure,
          'failure',
          isA<RequestCancelled>().having(
            (cancelled) => cancelled.reason,
            'reason',
            'gone',
          ),
        ),
      );
      expect(link.requests, isEmpty);
    });

    test(
      'a link stream that ends inside listen still gets its event',
      () async {
        final responses = await GraphQLClient(
          link: SynchronousLink(ticks(4)),
        ).subscribe(const TicksSubscription()).toList();
        expect((responses.single as GraphQLData<int>).data, 4);
      },
    );
  });

  test('mutate with a cancelled token answers without the link', () async {
    final link = MockLink();
    final response = await GraphQLClient(link: link).mutate(
      const RenameMutation('a'),
      cancelToken: CancelToken()..cancel(),
    );
    expect(
      response,
      isA<GraphQLTransportFailure<String>>().having(
        (failure) => failure.failure,
        'failure',
        isA<RequestCancelled>(),
      ),
    );
    expect(link.requests, isEmpty);
  });

  group('the extensions and the context of a result', () {
    final context = LinkContext([HttpResponseInfo(200)]);
    final extensions = JsonObject({'trace': const JsonString('t')});

    test('reach GraphQLErrors from errors without data', () async {
      final link = MockLink()
        ..add(
          LinkPayload(
            ExecutionResult(
              null,
              errors: [GraphQLError('x')],
              extensions: extensions,
            ),
            context: context,
          ),
        );
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLErrors<String>>()
            .having((errors) => errors.extensions, 'extensions', extensions)
            .having((errors) => errors.context, 'context', same(context)),
      );
    });

    test('reach GraphQLErrors from a request error', () async {
      final link = MockLink()
        ..add(
          LinkPayload(
            RequestErrorResult(
              errors: [GraphQLError('x')],
              extensions: extensions,
            ),
            context: context,
          ),
        );
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLErrors<String>>()
            .having((errors) => errors.extensions, 'extensions', extensions)
            .having((errors) => errors.context, 'context', same(context)),
      );
    });
  });
}
