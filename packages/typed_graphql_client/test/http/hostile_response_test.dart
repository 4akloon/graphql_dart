import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_transport.dart';
import '../support/test_operations.dart';

/// Answers a server could send by mistake or on purpose (spec section 14):
/// each one ends in a typed response, never a thrown exception.
void main() {
  late FakeTransport transport;

  setUp(() => transport = FakeTransport());

  GraphQLClient client({int maxResponseBytes = 1 << 20}) => GraphQLClient(
    link: HttpLink(
      uri: Uri.parse('https://example.com/graphql'),
      transport: transport,
      maxResponseBytes: maxResponseBytes,
    ),
  );

  Future<GraphQLResponse<String>> query({int maxResponseBytes = 1 << 20}) =>
      client(maxResponseBytes: maxResponseBytes).query(const HelloQuery());

  void answerBytes(
    List<int> bytes, {
    String contentType = 'application/graphql-response+json',
  }) => transport.answerWith(
    (request) async => TransportResponse(
      statusCode: 200,
      headers: {'content-type': contentType},
      body: Stream.value(bytes),
    ),
  );

  Future<ClientFailure> failureOf(Future<GraphQLResponse<String>> response) =>
      response.then(
        (response) => switch (response) {
          GraphQLTransportFailure(:final failure) => failure,
          _ => throw StateError('Expected a failure, got $response.'),
        },
      );

  Future<DiagnosticCode> codeOf(Future<GraphQLResponse<String>> response) =>
      failureOf(response).then((failure) => failure.code);

  group('size', () {
    test('a body past the limit is GQL463', () async {
      transport.answer('{"data":{"hello":"${'x' * 2000}"}}');
      expect(
        await codeOf(query(maxResponseBytes: 1000)),
        DiagnosticCode.responseTooLarge,
      );
    });

    test('an endless body is GQL463 and is cancelled', () async {
      var isCancelled = false;
      Stream<List<int>> endless() async* {
        try {
          while (true) {
            yield List.filled(64 * 1024, 32);
          }
        } finally {
          isCancelled = true;
        }
      }

      transport.answerWith(
        (request) async => TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/graphql-response+json'},
          body: endless(),
        ),
      );
      expect(await codeOf(query()), DiagnosticCode.responseTooLarge);
      expect(isCancelled, isTrue);
    });
  });

  group('text', () {
    for (final (name, body) in [
      ('an empty body', ''),
      ('text that is not JSON', 'Internal error'),
      ('an unfinished object', '{"data":'),
      ('100000 open braces', '{' * 100000),
      ('100000 open brackets', '[' * 100000),
    ]) {
      test('$name is GQL464', () async {
        transport.answer(body);
        expect(await codeOf(query()), DiagnosticCode.malformedResponse);
      });
    }

    test('bytes that are not UTF-8 are GQL464', () async {
      answerBytes([0x7b, 0xff, 0xfe, 0x7d]);
      expect(await codeOf(query()), DiagnosticCode.malformedResponse);
    });

    // Dart's UTF-8 decoder drops a leading byte order mark, which RFC 8259
    // section 8.1 lets a JSON parser ignore.
    test('a leading byte order mark is ignored', () async {
      answerBytes([0xef, 0xbb, 0xbf, ...utf8.encode('{"data":{"hello":"x"}}')]);
      expect(await query(), isA<GraphQLData<String>>());
    });
  });

  group('shape', () {
    for (final (name, body) in [
      ('a JSON array', '[]'),
      ('a JSON number', '1'),
      ('a JSON string', '"data"'),
      ('an object without data or errors', '{}'),
      ('data that is not an object', '{"data":[]}'),
      ('errors that are not a list', '{"data":{},"errors":{}}'),
      ('an error without a message', '{"data":{},"errors":[{}]}'),
      (
        'a message that is not a string',
        '{"data":{},"errors":[{"message":1}]}',
      ),
      (
        'a path with a boolean',
        '{"data":{},"errors":[{"message":"m","path":[true]}]}',
      ),
      (
        'a location that is not an object',
        '{"data":{},"errors":[{"message":"m","locations":[1]}]}',
      ),
      ('extensions that are not an object', '{"data":{},"extensions":[]}'),
    ]) {
      test('$name is GQL464', () async {
        transport.answer(body);
        expect(await codeOf(query()), DiagnosticCode.malformedResponse);
      });
    }

    test('a malformed error names the path of the bad value', () async {
      transport.answer('{"data":{},"errors":[{"message":1}]}');
      final failure = await failureOf(query());
      expect(failure, isA<ResponseFormatFailure>());
      expect((failure as ResponseFormatFailure).path, const [
        PathKey('errors'),
        PathIndex(0),
        PathKey('message'),
      ]);
    });

    test('null data without errors is GQL464', () async {
      transport.answer('{"data":null}');
      expect(await codeOf(query()), DiagnosticCode.malformedResponse);
    });

    test('an empty list of errors without data is GQL464', () async {
      transport.answer('{"errors":[]}');
      expect(await codeOf(query()), DiagnosticCode.malformedResponse);
    });

    test('data of the wrong shape is a data format failure', () async {
      transport.answer('{"data":{"hello":7}}');
      final failure = await failureOf(query());
      expect(failure, isA<DataFormatFailure>());
      expect(failure.code, DiagnosticCode.dataShapeMismatch);
    });

    test('data without the selected field is a data format failure', () async {
      transport.answer('{"data":{}}');
      expect(await failureOf(query()), isA<DataFormatFailure>());
    });
  });

  group('content type and status', () {
    for (final (name, type) in [
      ('a missing content type', ''),
      ('an HTML page', 'text/html'),
      ('a malformed content type', ';;=;'),
      ('a charset other than UTF-8', 'application/json; charset=latin1'),
    ]) {
      test('$name with 200 is GQL462', () async {
        transport.answer('{"data":{"hello":"x"}}', contentType: type);
        expect(await codeOf(query()), DiagnosticCode.unsupportedResponseType);
      });
    }

    test('a 500 with JSON is an HTTP status failure', () async {
      transport.answer(
        '{"data":{"hello":"x"}}',
        status: 500,
        contentType: 'application/json',
      );
      final failure = await failureOf(query());
      expect(failure, isA<HttpStatusFailure>());
      expect((failure as HttpStatusFailure).statusCode, 500);
    });

    test('a 401 with a GraphQL response is read as the response', () async {
      transport.answer(
        '{"errors":[{"message":"Unauthorized"}]}',
        status: 401,
      );
      final response = await query();
      expect(response, isA<GraphQLErrors<String>>());
      expect(
        (response as GraphQLErrors<String>).errors.single.message,
        'Unauthorized',
      );
    });
  });

  test('a body stream that throws an exception is a network failure', () async {
    transport.answerWith(
      (request) async => TransportResponse(
        statusCode: 200,
        headers: {'content-type': 'application/graphql-response+json'},
        body: Stream.error(const FormatException('connection reset')),
      ),
    );
    expect(await codeOf(query()), DiagnosticCode.networkFailure);
  });

  test(
    'a body that ends after the first chunk of an object is GQL464',
    () async {
      final body = StreamController<List<int>>();
      transport.answerWith(
        (request) async => TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/graphql-response+json'},
          body: body.stream,
        ),
      );
      final response = query();
      body.add(utf8.encode('{"data":{"hel'));
      await body.close();
      expect(await codeOf(response), DiagnosticCode.malformedResponse);
    },
  );
}
