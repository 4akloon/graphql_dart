import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

/// Answers every request with a new stream it keeps, so a test can feed
/// it and see whether it was cancelled.
final class OpenLink extends Link {
  final List<StreamController<LinkResult>> controllers = [];
  int cancelCount = 0;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    final controller = StreamController<LinkResult>(
      onCancel: () => cancelCount++,
    );
    controllers.add(controller);
    return controller.stream;
  }
}

void main() {
  LinkResult ticks(int value) =>
      LinkPayload(ExecutionResult(JsonObject({'ticks': JsonNumber(value)})));

  Matcher cancelledWith(Object? reason) =>
      isA<GraphQLTransportFailure<Object>>().having(
        (failure) => failure.failure,
        'failure',
        isA<RequestCancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          reason,
        ),
      );

  group('a cancel token', () {
    test(
      'already cancelled answers at once without calling the link',
      () async {
        final link = MockLink();
        final token = CancelToken()..cancel('gone');
        final response = await GraphQLClient(
          link: link,
        ).query(const HelloQuery(), cancelToken: token);
        expect(response, cancelledWith('gone'));
        expect(link.requests, isEmpty);
      },
    );

    test('cancelled while waiting answers and cancels the link', () async {
      final link = OpenLink();
      final token = CancelToken();
      final pending = GraphQLClient(
        link: link,
      ).query(const HelloQuery(), cancelToken: token);
      await Future<void>.delayed(Duration.zero);
      token.cancel('late');
      expect(await pending, cancelledWith('late'));
      expect(link.cancelCount, 1);
    });

    test('is released once the call completes', () async {
      final link = MockLink()
        ..addData(JsonObject({'hello': const JsonString('a')}));
      final token = CancelToken();
      await GraphQLClient(
        link: link,
      ).query(const HelloQuery(), cancelToken: token);
      expect(token.listenerCount, 0);
    });

    test('ends a subscription with the failure as its last event', () async {
      final link = OpenLink();
      final token = CancelToken();
      final events = <GraphQLResponse<int>>[];
      final done = Completer<void>();
      GraphQLClient(link: link)
          .subscribe(const TicksSubscription(), cancelToken: token)
          .listen(events.add, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);
      link.controllers.single.add(ticks(1));
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await done.future;
      expect(events, hasLength(2));
      expect(events.last, cancelledWith(null));
      expect(link.cancelCount, 1);
    });
  });

  group('subscribe', () {
    test('calls the link only when listened to', () async {
      final link = OpenLink();
      final responses = GraphQLClient(
        link: link,
      ).subscribe(const TicksSubscription());
      await Future<void>.delayed(Duration.zero);
      expect(link.controllers, isEmpty);
      final subscription = responses.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(link.controllers, hasLength(1));
      await subscription.cancel();
    });

    test('gives one response per event', () async {
      final link = MockLink()
        ..addStream(Stream.fromIterable([ticks(1), ticks(2), ticks(3)]));
      final responses = await GraphQLClient(
        link: link,
      ).subscribe(const TicksSubscription()).toList();
      expect(
        [
          for (final response in responses) (response as GraphQLData<int>).data,
        ],
        [1, 2, 3],
      );
    });

    test('cancelling the subscription cancels the link stream', () async {
      final link = OpenLink();
      final subscription = GraphQLClient(
        link: link,
      ).subscribe(const TicksSubscription()).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(link.cancelCount, 1);
    });
  });
}
