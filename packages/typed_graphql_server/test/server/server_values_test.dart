import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  group('RequestInfo', () {
    final info = RequestInfo(
      method: 'POST',
      uri: Uri.parse('http://localhost/graphql'),
      headers: {'Content-Type': 'application/json', 'X-Token': 'a'},
    );

    test('lower-cases the header names', () {
      expect(info.headers.keys, ['content-type', 'x-token']);
    });

    test('finds a header by any case', () {
      expect(info.header('CONTENT-type'), 'application/json');
    });

    test('a missing header is null', () {
      expect(info.header('accept'), isNull);
    });

    test('the headers are unmodifiable', () {
      expect(() => info.headers['a'] = 'b', throwsUnsupportedError);
    });

    test('keeps the method as given', () {
      expect(RequestInfo(method: 'get', uri: Uri()).method, 'get');
    });

    test('has no connection parameters by default', () {
      expect(info.connectionParams, isNull);
    });

    test('carries the connection parameters it is given', () {
      final params = JsonObject({'token': const JsonString('a')});
      expect(
        RequestInfo(
          method: 'GET',
          uri: Uri(),
          connectionParams: params,
        ).connectionParams,
        params,
      );
    });
  });

  group('SingleResponse', () {
    final payload = ExecutionResult(JsonObject({'a': JsonNumber(1)}));

    test('the body is the payload written', () {
      expect(SingleResponse(payload).body, payload.toJson());
    });

    test('lower-cases the header names', () {
      expect(
        SingleResponse(payload, headers: {'Allow': 'POST'}).headers,
        {'allow': 'POST'},
      );
    });

    test('the headers are unmodifiable', () {
      expect(
        () => SingleResponse(payload).headers['a'] = 'b',
        throwsUnsupportedError,
      );
    });

    test('withHeaders merges, lower-cases and lets new values win', () {
      final response = SingleResponse(
        payload,
        outcome: ServerOutcome.methodNotAllowed,
        headers: {'allow': 'GET', 'x-a': '1'},
      ).withHeaders({'Allow': 'POST', 'X-B': '2'});
      expect(response.headers, {'allow': 'POST', 'x-a': '1', 'x-b': '2'});
    });

    test('withHeaders keeps the subclass, payload and outcome', () {
      final ServerResponse response = SingleResponse(
        payload,
        outcome: ServerOutcome.requestError,
      ).withHeaders({'a': 'b'});
      expect(response, isA<SingleResponse>());
      expect((response as SingleResponse).payload, same(payload));
      expect(response.outcome, ServerOutcome.requestError);
    });
  });

  group('StreamResponse', () {
    const results = Stream<ExecutionResult>.empty();

    test('its outcome is executed', () {
      expect(StreamResponse(results).outcome, ServerOutcome.executed);
    });

    test('withHeaders keeps the subclass and the stream', () {
      final ServerResponse response = StreamResponse(
        results,
      ).withHeaders({'X-A': '1'});
      expect(response, isA<StreamResponse>());
      expect((response as StreamResponse).results, same(results));
      expect(response.headers, {'x-a': '1'});
    });
  });

  test('ServerRequest holds the parameters, info and signal', () {
    final signal = CancelSignal();
    final info = RequestInfo(method: 'GET', uri: Uri());
    const params = GraphQLRequest(query: '{a}');
    final request = ServerRequest(
      params: params,
      info: info,
      cancelSignal: signal,
    );
    expect(request.params, same(params));
    expect(request.info, same(info));
    expect(request.cancelSignal, same(signal));
  });
}
