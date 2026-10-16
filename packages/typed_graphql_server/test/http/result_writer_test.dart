import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/http/response_media_type.dart';
import 'package:typed_graphql_server/src/http/result_writer.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final writer = ResultWriter(usesPartialSuccessStatus: true);
  const graphql = ResponseMediaType.graphqlResponseJson;
  const legacy = ResponseMediaType.json;

  GraphQLError error(String? code) => GraphQLError(
    'Problem.',
    extensions: code == null ? null : JsonObject({'code': JsonString(code)}),
  );

  SingleResponse executed({List<GraphQLError> errors = const []}) =>
      SingleResponse(
        ExecutionResult(
          errors.isEmpty ? JsonObject({'a': JsonNumber(1)}) : null,
          errors: errors,
        ),
      );

  SingleResponse refused(String? code) => SingleResponse(
    RequestErrorResult(errors: [error(code)]),
    outcome: ServerOutcome.requestError,
  );

  group('status', () {
    final rows = <String, (SingleResponse, int, int)>{
      'executed without errors': (executed(), 200, 200),
      'executed with errors': (executed(errors: [error(null)]), 294, 200),
      'a syntax error': (refused('GQL010'), 400, 400),
      'CSRF prevention': (refused('GQL403'), 403, 403),
      'a validation error': (refused('GQL200'), 422, 422),
      'a refusal of the pipeline': (refused('GQL431'), 422, 422),
      'a request error without a code': (refused(null), 422, 422),
      'a GET mutation': (
        SingleResponse(
          RequestErrorResult(errors: [error('GQL402')]),
          outcome: ServerOutcome.methodNotAllowed,
        ),
        405,
        405,
      ),
      'an internal error': (
        SingleResponse(
          RequestErrorResult(errors: [error('GQL330')]),
          outcome: ServerOutcome.internalError,
        ),
        500,
        500,
      ),
    };
    for (final MapEntry(:key, :value) in rows.entries) {
      final (response, graphqlStatus, legacyStatus) = value;
      test('$key is $graphqlStatus for graphql-response+json', () {
        expect(writer.single(response, graphql).status, graphqlStatus);
      });
      test('$key is $legacyStatus for application/json', () {
        expect(writer.single(response, legacy).status, legacyStatus);
      });
    }

    test('is 200 for errors when the partial success status is off', () {
      final off = ResultWriter(usesPartialSuccessStatus: false);
      expect(off.single(executed(errors: [error(null)]), graphql).status, 200);
    });
  });

  group('headers', () {
    test('write the content type of each media type', () {
      expect(
        writer.single(executed(), graphql).headers['content-type'],
        'application/graphql-response+json; charset=utf-8',
      );
      expect(
        writer.single(executed(), legacy).headers['content-type'],
        'application/json; charset=utf-8',
      );
    });

    test('copy the headers of the response, such as allow', () {
      final response = SingleResponse(
        RequestErrorResult(errors: [error('GQL402')]),
        outcome: ServerOutcome.methodNotAllowed,
        headers: {'Allow': 'POST', 'x-extra': '1'},
      );
      final headers = writer.single(response, legacy).headers;
      expect(headers['allow'], 'POST');
      expect(headers['x-extra'], '1');
    });

    test('let our content type win over an extension\'s', () {
      final response = SingleResponse(
        ExecutionResult(null),
        headers: {'Content-Type': 'text/plain'},
      );
      expect(
        writer.single(response, graphql).headers['content-type'],
        'application/graphql-response+json; charset=utf-8',
      );
    });
  });

  group('body', () {
    test('is the JSON of the payload', () {
      final body = writer.single(executed(), legacy).body as FixedBody;
      expect(utf8.decode(body.bytes), '{"data":{"a":1}}');
    });

    test('is UTF-8 encoded', () {
      final response = SingleResponse(
        ExecutionResult(JsonObject({'a': const JsonString('é')})),
      );
      final body = writer.single(response, legacy).body as FixedBody;
      expect(body.bytes, utf8.encode('{"data":{"a":"é"}}'));
    });
  });

  group('batch', () {
    test('is a 200 with a JSON array in order', () {
      final response = writer.batch([
        ExecutionResult(JsonObject({'a': JsonNumber(1)})),
        RequestErrorResult(errors: [error('GQL431')]),
      ], graphql);
      expect(response.status, 200);
      expect(
        response.headers['content-type'],
        'application/graphql-response+json; charset=utf-8',
      );
      expect(
        utf8.decode((response.body as FixedBody).bytes),
        '[{"data":{"a":1}},'
        '{"errors":[{"message":"Problem.","extensions":{"code":"GQL431"}}]}]',
      );
    });

    test('is 200 even when every item failed', () {
      final response = writer.batch([
        RequestErrorResult(errors: [error('GQL200')]),
      ], legacy);
      expect(response.status, 200);
    });
  });
}
