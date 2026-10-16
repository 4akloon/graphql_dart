import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/src/http/media_type.dart';
import 'package:typed_graphql_client/src/http/response_reader.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  const reader = ResponseReader(maxBytes: 64, maxDepth: 8);
  const graphQLResponse = 'application/graphql-response+json';

  TransportResponse answer(
    String body, {
    int status = 200,
    String? type = graphQLResponse,
  }) => TransportResponse(
    statusCode: status,
    headers: {'content-type': ?type},
    body: Stream.value(utf8.encode(body)),
  );

  ClientFailure failureOf(LinkResult result) => switch (result) {
    LinkFailure(:final failure) => failure,
    LinkPayload() => fail('expected a failure, got $result'),
  };

  ResponsePayload payloadOf(LinkResult result) => switch (result) {
    LinkPayload(:final payload) => payload,
    LinkFailure() => fail('expected a payload, got $result'),
  };

  group('MediaType', () {
    test('reads the essence in lower case without parameters', () {
      expect(
        MediaType.parse(' Application/JSON ; charset=utf-8').essence,
        'application/json',
      );
    });

    test('reads a quoted charset in lower case', () {
      expect(MediaType.parse('text/plain; charset="UTF-8"').charset, 'utf-8');
    });

    test('has no essence without a header', () {
      expect(MediaType.parse(null).essence, isNull);
    });

    test('is not UTF-8 with another charset', () {
      expect(
        MediaType.parse('application/json; charset=latin1').isUtf8,
        isFalse,
      );
    });
  });

  group('reads', () {
    test('a GraphQL response with its status and headers', () async {
      final result = await reader.read(answer('{"data":{"a":1}}'));
      final info = (result as LinkPayload).context.entry<HttpResponseInfo>();
      expect(
        result.payload,
        ExecutionResult(JsonObject({'a': JsonNumber(1)})),
      );
      expect(info?.statusCode, 200);
      expect(info?.headers, {'content-type': graphQLResponse});
    });

    test('a GraphQL response whatever its status', () async {
      final result = await reader.read(
        answer('{"errors":[{"message":"bad"}]}', status: 400),
      );
      expect(
        payloadOf(result),
        RequestErrorResult(errors: [GraphQLError('bad')]),
      );
    });

    test('JSON with a 2xx status', () async {
      final result = await reader.read(
        answer(
          '{"data":null,"errors":[{"message":"x"}]}',
          type: 'application/json',
        ),
      );
      expect(payloadOf(result), isA<ExecutionResult>());
    });
  });

  group('refuses', () {
    test('JSON with another status as an HTTP status failure', () async {
      final result = await reader.read(
        answer('{"data":{}}', status: 500, type: 'application/json'),
      );
      expect(failureOf(result), isA<HttpStatusFailure>());
    });

    test(
      'another type with an error status as an HTTP status failure',
      () async {
        final failure = failureOf(
          await reader.read(answer('<html>', status: 502, type: 'text/html')),
        );
        expect((failure as HttpStatusFailure).statusCode, 502);
      },
    );

    test('another type with a 2xx status as GQL462', () async {
      final failure = failureOf(
        await reader.read(answer('<html>', type: 'text/html')),
      );
      expect(failure.code, DiagnosticCode.unsupportedResponseType);
      expect(
        failure.message,
        'The response has content type "text/html", which is not a GraphQL '
        'response.',
      );
    });

    test('a missing type as GQL462', () async {
      final failure = failureOf(await reader.read(answer('{}', type: null)));
      expect(failure.message, 'The response has no content type.');
    });

    test('a charset other than UTF-8 as GQL462', () async {
      final failure = failureOf(
        await reader.read(
          answer('{}', type: '$graphQLResponse; charset=latin1'),
        ),
      );
      expect(failure.code, DiagnosticCode.unsupportedResponseType);
    });

    test('a body past the limit as GQL463 and cancels it', () async {
      var isCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => isCancelled = true,
      );
      final result = reader.read(
        TransportResponse(
          statusCode: 200,
          headers: {'content-type': graphQLResponse},
          body: body.stream,
        ),
      );
      body
        ..add(List.filled(40, 32))
        ..add(List.filled(40, 32));
      final failure = failureOf(await result);
      expect(failure.code, DiagnosticCode.responseTooLarge);
      expect(failure.message, 'The response is longer than 64 bytes.');
      expect(isCancelled, isTrue);
      await body.close();
    });

    test('bytes that are not UTF-8 as GQL464', () async {
      final failure = failureOf(
        await reader.read(
          TransportResponse(
            statusCode: 200,
            headers: {'content-type': graphQLResponse},
            body: Stream.value([0x7b, 0xff, 0x7d]),
          ),
        ),
      );
      expect(failure.code, DiagnosticCode.malformedResponse);
      expect(failure.message, 'The response is not UTF-8.');
    });

    test('nesting past the depth as GQL464', () async {
      final failure = failureOf(await reader.read(answer('[' * 20)));
      expect(failure.code, DiagnosticCode.malformedResponse);
    });

    test(
      'JSON that is not a GraphQL response as GQL464 with its path',
      () async {
        final failure = failureOf(
          await reader.read(answer('{"data":{},"errors":[{"message":1}]}')),
        );
        expect(failure.code, DiagnosticCode.malformedResponse);
        expect((failure as ResponseFormatFailure).path, [
          const PathKey('errors'),
          const PathIndex(0),
          const PathKey('message'),
        ]);
      },
    );
  });

  test('lets an exception of the body stream through', () {
    final result = reader.read(
      TransportResponse(
        statusCode: 200,
        headers: {'content-type': graphQLResponse},
        body: Stream.error(const FormatException('connection reset')),
      ),
    );
    expect(result, throwsA(isA<FormatException>()));
  });
}
