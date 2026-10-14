import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  DecodeResult<ResponsePayload> decode(String text) =>
      ResponsePayload.decode(json(text));

  final data = JsonObject({
    'hero': JsonObject({'name': const JsonString('R2-D2')}),
  });
  final error = GraphQLError('Boom', path: const [PathKey('hero')]);

  group('ExecutionResult', () {
    test('writes errors first, then data', () {
      expect(
        ExecutionResult(data, errors: [error]).toJson().toString(),
        '{"errors":[{"message":"Boom","path":["hero"]}],'
        '"data":{"hero":{"name":"R2-D2"}}}',
      );
    });

    test('leaves out empty errors and writes null data', () {
      expect(
        ExecutionResult(data).toJson().toString(),
        '{"data":{"hero":{"name":"R2-D2"}}}',
      );
      expect(
        ExecutionResult(null, errors: [error]).toJson().toString(),
        '{"errors":[{"message":"Boom","path":["hero"]}],"data":null}',
      );
    });

    test('is read when data is present, even null', () {
      expect(
        decode(
          '{"data": null, "errors": [{"message": "Boom", "path": ["hero"]}]}',
        ),
        DecodeSuccess<ResponsePayload>(ExecutionResult(null, errors: [error])),
      );
      expect(
        decode('{"data": {"hero": {"name": "R2-D2"}}}'),
        DecodeSuccess<ResponsePayload>(ExecutionResult(data)),
      );
    });

    test('reads what toJson writes', () {
      final result = ExecutionResult(
        data,
        errors: [error],
        extensions: JsonObject({'cost': JsonNumber(3)}),
      );
      expect(
        ResponsePayload.decode(result.toJson()),
        DecodeSuccess<ResponsePayload>(result),
      );
    });

    test('rejects data that is not an object', () {
      expect(
        decode('{"data": []}'),
        const DecodeFailure('expected an object', path: [PathKey('data')]),
      );
    });

    test('places a bad error at its index', () {
      expect(
        decode('{"data": null, "errors": [{"message": "a"}, {}]}'),
        const DecodeFailure(
          'is required',
          path: [PathKey('errors'), PathIndex(1), PathKey('message')],
        ),
      );
    });
  });

  group('RequestErrorResult', () {
    test('writes errors and no data', () {
      expect(
        RequestErrorResult(errors: [error]).toJson().toString(),
        '{"errors":[{"message":"Boom","path":["hero"]}]}',
      );
    });

    test('requires at least one error', () {
      expect(() => RequestErrorResult(errors: const []), throwsArgumentError);
    });

    test('is read when data is absent', () {
      expect(
        decode('{"errors": [{"message": "Boom", "path": ["hero"]}]}'),
        DecodeSuccess<ResponsePayload>(RequestErrorResult(errors: [error])),
      );
    });

    test('rejects a payload with neither data nor errors', () {
      for (final text in ['{}', '{"errors": []}', '{"errors": null}']) {
        expect(decode(text), isA<DecodeFailure>(), reason: text);
      }
    });

    test('reports a bad error before a missing data', () {
      expect(
        decode('{"errors": [{"message": 1}]}'),
        const DecodeFailure(
          'expected a string',
          path: [PathKey('errors'), PathIndex(0), PathKey('message')],
        ),
      );
    });
  });

  test('a switch over ResponsePayload is exhaustive', () {
    String kind(ResponsePayload payload) => switch (payload) {
      ExecutionResult() => 'execution',
      RequestErrorResult() => 'request error',
    };
    expect(kind(ExecutionResult(null)), 'execution');
  });

  test('rejects a payload that is not an object', () {
    expect(decode('[]'), const DecodeFailure('expected an object'));
  });
}
