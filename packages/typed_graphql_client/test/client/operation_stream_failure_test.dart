import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'client_cancellation_test.dart' show OpenLink;

/// A link that throws before it returns a stream, as a non-async link may.
final class ThrowingLink extends Link {
  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) =>
      throw StateError('broken link');
}

/// A query whose generated decoder has a bug.
final class BrokenDecoderQuery extends GraphQLQuery<String> {
  const BrokenDecoderQuery();

  @override
  OperationDocument get document => HelloQuery.operationDocument;

  @override
  JsonObject get variablesJson => JsonObject(const {});

  @override
  DecodeResult<String> decodeData(JsonObject data) => throw TypeError();
}

void main() {
  group('a link that throws from request', () {
    test('completes a query with the error', () async {
      final token = CancelToken();
      await expectLater(
        GraphQLClient(
          link: ThrowingLink(),
        ).query(const HelloQuery(), cancelToken: token),
        throwsA(isA<StateError>()),
      );
      expect(token.listenerCount, 0);
    });

    test('puts the error into the subscription stream', () async {
      final token = CancelToken();
      await expectLater(
        GraphQLClient(
          link: ThrowingLink(),
        ).subscribe(const TicksSubscription(), cancelToken: token),
        emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
      );
      expect(token.listenerCount, 0);
    });
  });

  group('a decoder that throws', () {
    test('completes the call with the error and cancels the link', () async {
      final link = OpenLink();
      final pending = GraphQLClient(link: link).query(
        const BrokenDecoderQuery(),
      );
      await Future<void>.delayed(Duration.zero);
      link.controllers.single.add(
        LinkPayload(
          ExecutionResult(JsonObject({'hello': const JsonString('a')})),
        ),
      );
      await expectLater(pending, throwsA(isA<TypeError>()));
      expect(link.cancelCount, 1);
    });
  });
}
