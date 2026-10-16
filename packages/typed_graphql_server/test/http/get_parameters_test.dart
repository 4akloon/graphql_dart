import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/http/get_parameters.dart';
import 'package:typed_graphql_server/src/http/request_decoding.dart';

void main() {
  const parameters = GetParameters(8);

  RequestDecoding decode(Map<String, Object> query) =>
      parameters.decode(Uri(path: '/graphql', queryParameters: query));

  GraphQLRequest request(Map<String, Object> query) =>
      (decode(query) as DecodedRequest).request;

  void expectRefusal(Map<String, Object> query, String message) {
    final refusal = decode(query) as DecodingRefusal;
    expect(
      (refusal.status, refusal.code, refusal.message),
      (
        422,
        DiagnosticCode.malformedRequestParameters,
        message,
      ),
    );
  }

  group('reading', () {
    test('reads the four GraphQL parameters', () {
      expect(
        request({
          'query': r'query Q($a: String) { greet(name: $a) }',
          'operationName': 'Q',
          'variables': '{"a":"x"}',
          'extensions': '{"b":1}',
        }),
        GraphQLRequest(
          query: r'query Q($a: String) { greet(name: $a) }',
          operationName: 'Q',
          variables: JsonObject({'a': const JsonString('x')}),
          extensions: JsonObject({'b': JsonNumber(1)}),
        ),
      );
    });

    test('ignores every other parameter', () {
      expect(
        request({'query': '{hello}', 'utm_source': 'mail', 'a': 'b'}),
        const GraphQLRequest(query: '{hello}'),
      );
    });

    test('reads a request without a query string as all absent', () {
      expect(
        parameters.decode(Uri.parse('/graphql')),
        isA<DecodedRequest>().having(
          (decoded) => decoded.request,
          'request',
          const GraphQLRequest(),
        ),
      );
    });

    test('treats an empty value as absent', () {
      expect(
        request({
          'query': '{hello}',
          'operationName': '',
          'variables': '',
          'extensions': '',
        }),
        const GraphQLRequest(query: '{hello}'),
      );
    });

    test('reads operationName=null as the name "null"', () {
      expect(request({'operationName': 'null'}).operationName, 'null');
    });

    test('keeps a lone percent sign in the query', () {
      expect(
        (parameters.decode(
          Uri.parse('/graphql?query=%'),
        ) as DecodedRequest).request.query,
        '%',
      );
    });
  });

  group('refusing', () {
    test('refuses a parameter given twice', () {
      expectRefusal({
        'query': ['{a}', '{b}'],
      }, 'The parameter query is given more than once.');
    });

    test('refuses a repeated parameter even when one value is empty', () {
      expectRefusal({
        'operationName': ['', 'Q'],
      }, 'The parameter operationName is given more than once.');
    });

    test('refuses variables that are not a JSON object', () {
      expectRefusal({
        'variables': '[1]',
      }, 'The parameter variables is not a JSON object.');
    });

    test('refuses extensions that are a JSON string', () {
      expectRefusal({
        'extensions': '"x"',
      }, 'The parameter extensions is not a JSON object.');
    });

    test('refuses variables that are not JSON', () {
      final refusal = decode({'variables': '{'}) as DecodingRefusal;
      expect(
        refusal.message,
        startsWith('The parameter variables is not valid JSON: '),
      );
    });

    test('refuses variables nested deeper than maxJsonDepth', () {
      final refusal = decode({
        'variables': '${'{"a":' * 20}1${'}' * 20}',
      }) as DecodingRefusal;
      expect(
        refusal.message,
        'The parameter variables is not valid JSON: arrays and objects are '
        'nested deeper than 8.',
      );
    });

    test('refuses a query string that is not valid UTF-8', () {
      final refusal =
          parameters.decode(Uri.parse('/graphql?query=%FF')) as DecodingRefusal;
      expect(
        (refusal.status, refusal.code, refusal.message),
        (
          422,
          DiagnosticCode.malformedRequestParameters,
          'The query string is not valid UTF-8.',
        ),
      );
    });
  });
}
