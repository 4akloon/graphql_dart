import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  group('SplitLink', () {
    test('sends a request that passes the test to whenTrue', () async {
      final sockets = MockLink()..addData(JsonObject(const {}));
      final http = MockLink();
      final link = SplitLink(
        test: (request) => request.type == OperationType.subscription,
        whenTrue: sockets,
        whenFalse: http,
      );
      await link
          .request(LinkRequest.of(const TicksSubscription()), unterminated)
          .drain<void>();
      expect(sockets.requests, hasLength(1));
      expect(http.requests, isEmpty);
    });

    test('sends the other requests to whenFalse', () async {
      final sockets = MockLink();
      final http = MockLink()..addData(JsonObject(const {}));
      final link = SplitLink(
        test: (request) => request.type == OperationType.subscription,
        whenTrue: sockets,
        whenFalse: http,
      );
      await link
          .request(LinkRequest.of(const HelloQuery()), unterminated)
          .drain<void>();
      expect(http.requests, hasLength(1));
      expect(sockets.requests, isEmpty);
    });

    test('a branch gets the chain\'s forward', () async {
      final terminal = MockLink()..addData(JsonObject(const {}));
      final link = Link.from([
        SplitLink(
          test: (request) => true,
          whenTrue: ContextLink((request) => request.context),
          whenFalse: terminal,
        ),
        terminal,
      ]);
      await link
          .request(LinkRequest.of(const HelloQuery()), unterminated)
          .drain<void>();
      expect(terminal.requests, hasLength(1));
    });
  });

  group('ContextLink', () {
    test('forwards the request with the new context', () async {
      final terminal = MockLink()..addData(JsonObject(const {}));
      final link = Link.from([
        ContextLink(
          (request) async => request.context.withEntry(
            RequestHeaders({'authorization': 'Bearer t'}),
          ),
        ),
        terminal,
      ]);
      await link
          .request(LinkRequest.of(const HelloQuery()), unterminated)
          .drain<void>();
      expect(
        terminal.requests.single.context.entry<RequestHeaders>()?.values,
        {'authorization': 'Bearer t'},
      );
    });

    test(
      'an exception of update is a network failure, not forwarded',
      () async {
        final terminal = MockLink();
        final link = Link.from([
          ContextLink((request) => throw const FormatException('no token')),
          terminal,
        ]);
        final results = await link
            .request(LinkRequest.of(const HelloQuery()), unterminated)
            .toList();
        expect(results.single, isA<LinkFailure>());
        expect(
          (results.single as LinkFailure).failure,
          isA<NetworkFailure>(),
        );
        expect(terminal.requests, isEmpty);
      },
    );

    test('cancelling cancels the forwarded stream', () async {
      var isCancelled = false;
      final controller = StreamController<LinkResult>(
        onCancel: () => isCancelled = true,
      );
      final link = ContextLink((request) => request.context);
      final subscription = link
          .request(
            LinkRequest.of(const HelloQuery()),
            (request) => controller.stream,
          )
          .listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(isCancelled, isTrue);
      await controller.close();
    });

    test('a cancel during a pending update forwards nothing', () async {
      final update = Completer<LinkContext>();
      var forwardCount = 0;
      final link = ContextLink((request) => update.future);
      final subscription = link
          .request(LinkRequest.of(const HelloQuery()), (request) {
            forwardCount++;
            return const Stream<LinkResult>.empty();
          })
          .listen((_) {});
      await Future<void>.delayed(Duration.zero);
      // The cancel future completes only when the update does.
      final cancelled = subscription.cancel();
      update.complete(const LinkContext.empty());
      await cancelled;
      expect(forwardCount, 0);
    });
  });
}
