import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  DecodeResult<GraphQLRequest> decode(String text) =>
      GraphQLRequest.decode(json(text));

  test('writes only the fields that are set', () {
    final request = GraphQLRequest(
      query: r'query Hero($id: ID!) { hero(id: $id) { name } }',
      operationName: 'Hero',
      variables: JsonObject({'id': const JsonString('1')}),
    );
    expect(
      request.toJson().toString(),
      r'{"query":"query Hero($id: ID!) { hero(id: $id) { name } }",'
      '"operationName":"Hero","variables":{"id":"1"}}',
    );
    expect(const GraphQLRequest().toJson().toString(), '{}');
  });

  test('reads what toJson writes', () {
    final request = GraphQLRequest(
      query: '{ a }',
      operationName: 'A',
      variables: JsonObject({'x': JsonNumber(1)}),
      extensions: JsonObject({'k': const JsonBool(true)}),
    );
    expect(GraphQLRequest.decode(request.toJson()), DecodeSuccess(request));
  });

  test('reads a persisted query without a document', () {
    expect(
      decode(
        '{"extensions": {"persistedQuery": '
        '{"version": 1, "sha256Hash": "abc"}}}',
      ),
      DecodeSuccess(
        GraphQLRequest(
          extensions: JsonObject({
            'persistedQuery': JsonObject({
              'version': JsonNumber(1),
              'sha256Hash': const JsonString('abc'),
            }),
          }),
        ),
      ),
    );
  });

  test('treats null fields as absent', () {
    expect(
      decode(
        '{"query": "{ a }", "operationName": null, "variables": null, '
        '"extensions": null}',
      ),
      const DecodeSuccess(GraphQLRequest(query: '{ a }')),
    );
  });

  test('ignores keys it does not know, as GraphQL over HTTP requires', () {
    expect(
      decode('{"query": "{ a }", "id": 7}'),
      const DecodeSuccess(GraphQLRequest(query: '{ a }')),
    );
  });

  test('rejects mistyped fields with their path', () {
    expect(
      decode('{"query": 1}'),
      const DecodeFailure('expected a string', path: [PathKey('query')]),
    );
    expect(
      decode('{"variables": "x"}'),
      const DecodeFailure('expected an object', path: [PathKey('variables')]),
    );
    expect(decode('[]'), const DecodeFailure('expected an object'));
  });
}
