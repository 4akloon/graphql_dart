import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

/// Answers every request with the stream of [controller], recording it.
final class ControlledLink extends Link {
  ControlledLink(this.controller);

  final StreamController<LinkResult> controller;
  final List<LinkRequest> requests = [];

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    requests.add(request);
    return controller.stream;
  }
}

/// Forwards every request: a chain made only of it never terminates.
final class ForwardingLink extends Link {
  const ForwardingLink();

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) =>
      forward(request);
}

void main() {
  JsonObject hello(String value) => JsonObject({'hello': JsonString(value)});

  group('query', () {
    test('gives the decoded data', () async {
      final link = MockLink()..addData(hello('world'));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLData<String>>()
            .having((data) => data.data, 'data', 'world')
            .having((data) => data.hasErrors, 'hasErrors', isFalse),
      );
    });

    test('keeps the errors of partial data', () async {
      final link = MockLink()
        ..addData(hello('world'), errors: [GraphQLError('part failed')]);
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLData<String>>().having((data) => data.errors, 'errors', [
          GraphQLError('part failed'),
        ]),
      );
    });

    test('a request error is GraphQLErrors', () async {
      final link = MockLink()..addErrors([GraphQLError('syntax')]);
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLErrors<String>>().having(
          (errors) => errors.errors,
          'errors',
          [GraphQLError('syntax')],
        ),
      );
    });

    test('null data with errors is GraphQLErrors', () async {
      final link = MockLink()
        ..add(LinkPayload(ExecutionResult(null, errors: [GraphQLError('x')])));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(response, isA<GraphQLErrors<String>>());
    });

    test('null data without errors is a malformed response', () async {
      final link = MockLink()..add(LinkPayload(ExecutionResult(null)));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure.code,
          'code',
          DiagnosticCode.malformedResponse,
        ),
      );
    });

    test('data of the wrong shape is a data format failure that keeps the '
        'errors', () async {
      final link = MockLink()
        ..addData(
          JsonObject({'hello': JsonNumber(1)}),
          errors: [GraphQLError('x')],
        );
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure,
          'failure',
          isA<DataFormatFailure>()
              .having(
                (failure) => failure.decodeFailure.path,
                'path',
                [const PathKey('hello')],
              )
              .having((failure) => failure.errors, 'errors', [
                GraphQLError('x'),
              ]),
        ),
      );
    });

    test('a link failure is a transport failure', () async {
      final link = MockLink()..addFailure(HttpStatusFailure(502));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure,
          'failure',
          isA<HttpStatusFailure>(),
        ),
      );
    });

    test('sends the context and returns the result\'s', () async {
      final link = MockLink()
        ..add(
          LinkPayload(
            ExecutionResult(hello('world')),
            context: LinkContext([HttpResponseInfo(200)]),
          ),
        );
      final response = await GraphQLClient(link: link).query(
        const HelloQuery(),
        context: LinkContext([
          RequestHeaders({'x-a': '1'}),
        ]),
      );
      expect(
        link.requests.single.context.entry<RequestHeaders>()?.values,
        {'x-a': '1'},
      );
      expect(
        (response as GraphQLData<String>).context
            .entry<HttpResponseInfo>()
            ?.statusCode,
        200,
      );
    });

    test('a chain without a result is GQL469', () async {
      final link = ControlledLink(StreamController());
      unawaited(link.controller.close());
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure.code,
          'code',
          DiagnosticCode.linkEndedWithoutResult,
        ),
      );
    });

    test('an exception on the link stream is a network failure', () async {
      final link = ControlledLink(StreamController());
      link.controller.addError(const FormatException('reset'));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure,
          'failure',
          isA<NetworkFailure>(),
        ),
      );
    });

    test('a chain that forwards past its end is a StateError', () {
      final client = GraphQLClient(link: const ForwardingLink());
      expect(client.query(const HelloQuery()), throwsStateError);
    });

    test('takes the first result and cancels the link stream', () async {
      var isCancelled = false;
      final controller = StreamController<LinkResult>(
        onCancel: () => isCancelled = true,
      );
      controller.add(LinkPayload(ExecutionResult(hello('a'))));
      final response = await GraphQLClient(
        link: ControlledLink(controller),
      ).query(const HelloQuery());
      expect(response, isA<GraphQLData<String>>());
      expect(isCancelled, isTrue);
      await controller.close();
    });
  });

  test('mutate sends the mutation', () async {
    final link = MockLink()
      ..addData(JsonObject({'rename': const JsonString('Ada')}));
    final response = await GraphQLClient(
      link: link,
    ).mutate(const RenameMutation('Ada'));
    expect(link.requests.single.type, OperationType.mutation);
    expect(response, isA<GraphQLData<String>>());
  });

  test('answers under fake time without the real event loop', () {
    fakeAsync((async) {
      GraphQLResponse<String>? response;
      unawaited(
        GraphQLClient(link: MockLink()..addData(hello('world')))
            .query(const HelloQuery())
            .then((value) => response = value),
      );
      async.flushMicrotasks();
      expect(response, isA<GraphQLData<String>>());
    });
  });
}
