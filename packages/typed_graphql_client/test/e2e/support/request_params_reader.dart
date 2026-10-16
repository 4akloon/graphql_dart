import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

/// Reads the GraphQL parameters of a [TransportRequest] as GraphQL over HTTP
/// defines them: the JSON body of a `POST`, the query parameters of a `GET`.
final class RequestParamsReader {
  /// Creates the reader.
  const RequestParamsReader();

  /// The parameters of [request]; a request this client cannot have sent is
  /// a [StateError], since it is a bug of the test.
  Future<GraphQLRequest> read(TransportRequest request) async {
    final json = request.method == 'GET'
        ? _fromQuery(request.uri.queryParameters)
        : await _fromBody(request);
    return switch (GraphQLRequest.decode(json)) {
      DecodeSuccess(:final value) => value,
      DecodeFailure(:final message) => throw StateError(message),
    };
  }

  Future<JsonValue> _fromBody(TransportRequest request) async {
    final bytes = await (request.body ?? const Stream<List<int>>.empty())
        .expand((chunk) => chunk)
        .toList();
    return _parse(utf8.decode(bytes));
  }

  JsonValue _fromQuery(Map<String, String> parameters) => JsonObject({
    'query': ?_text(parameters['query']),
    'operationName': ?_text(parameters['operationName']),
    'variables': ?_json(parameters['variables']),
    'extensions': ?_json(parameters['extensions']),
  });

  JsonString? _text(String? value) => value == null ? null : JsonString(value);

  JsonValue? _json(String? value) => value == null ? null : _parse(value);

  JsonValue _parse(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    DecodeFailure(:final message) => throw StateError(message),
  };
}
