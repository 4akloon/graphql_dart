import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/http/json_body_decoder.dart';
import 'package:typed_graphql_server/src/http/request_decoding.dart';

void main() {
  const decoder = JsonBodyDecoder(maxJsonDepth: 8);

  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  DecodingRefusal refusal(Uint8List body) =>
      decoder.decode(body) as DecodingRefusal;

  void expectRefusal(
    Uint8List body,
    int status,
    DiagnosticCode code,
    String message,
  ) {
    expect(
      (refusal(body).status, refusal(body).code, refusal(body).message),
      (
        status,
        code,
        message,
      ),
    );
  }

  group('a request', () {
    test('is read from a JSON object', () {
      final decoded = decoder.decode(
        bytes(
          '{"query":"{hello}","operationName":"Q","variables":{"a":1},'
          '"extensions":{"b":true},"other":1}',
        ),
      );
      expect(
        (decoded as DecodedRequest).request,
        GraphQLRequest(
          query: '{hello}',
          operationName: 'Q',
          variables: JsonObject({'a': JsonNumber(1)}),
          extensions: JsonObject({'b': const JsonBool(true)}),
        ),
      );
    });

    test('reads null fields as absent', () {
      final decoded = decoder.decode(bytes('{"query":null}'));
      expect((decoded as DecodedRequest).request, const GraphQLRequest());
    });

    test('reads non-ASCII text', () {
      final decoded = decoder.decode(bytes('{"query":"{ é }"}'));
      expect((decoded as DecodedRequest).request.query, '{ é }');
    });
  });

  group('a body that is not JSON', () {
    test('is 400 when it is not valid UTF-8', () {
      expectRefusal(
        Uint8List.fromList([0x7B, 0xFF, 0x7D]),
        400,
        DiagnosticCode.malformedRequestBody,
        'The request body is not valid UTF-8.',
      );
    });

    test('is 400 when it starts with a byte-order mark', () {
      expectRefusal(
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('{}')]),
        400,
        DiagnosticCode.malformedRequestBody,
        'The request body is not valid JSON: it starts with a byte-order '
        'mark.',
      );
    });

    test('is 400 when it is not JSON', () {
      final result = refusal(bytes('{"query":'));
      expect(
        (result.status, result.code),
        (
          400,
          DiagnosticCode.malformedRequestBody,
        ),
      );
      expect(
        result.message,
        startsWith('The request body is not valid JSON: not JSON: '),
      );
    });

    test('is 400 when it is empty', () {
      expect(refusal(Uint8List(0)).code, DiagnosticCode.malformedRequestBody);
    });

    test('is 400 when it is nested deeper than maxJsonDepth', () {
      expectRefusal(
        bytes('${'[' * 100000}${']' * 100000}'),
        400,
        DiagnosticCode.malformedRequestBody,
        'The request body is not valid JSON: arrays and objects are nested '
        'deeper than 8.',
      );
    });
  });

  group('JSON that is not a request', () {
    test('is 422 when a field has the wrong type, naming the path', () {
      expectRefusal(
        bytes('{"query":1}'),
        422,
        DiagnosticCode.malformedRequestParameters,
        'The request is malformed: expected a string at query',
      );
    });

    test('is 422 when variables is not an object', () {
      expectRefusal(
        bytes('{"variables":[]}'),
        422,
        DiagnosticCode.malformedRequestParameters,
        'The request is malformed: expected an object at variables',
      );
    });

    test('is 422 for a string', () {
      expectRefusal(
        bytes('"{hello}"'),
        422,
        DiagnosticCode.malformedRequestParameters,
        'The request body must be a JSON object.',
      );
    });

    test('is 422 for null', () {
      expect(
        refusal(bytes('null')).message,
        'The request body must be a JSON object.',
      );
    });

    test('is 422 for an array when batching is off', () {
      expectRefusal(
        bytes('[{"query":"{hello}"}]'),
        422,
        DiagnosticCode.batchingDisabled,
        'Batched requests are not enabled.',
      );
    });
  });
}
