import 'package:typed_graphql/typed_graphql.dart';

/// One request a `PipelineTransport` served, as it went over the wire.
final class ServedRequest {
  /// Creates the record.
  const ServedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.params,
  });

  /// The HTTP method.
  final String method;

  /// The URL, with the query parameters of a `GET` request.
  final Uri uri;

  /// The headers, names in lower case.
  final Map<String, String> headers;

  /// The GraphQL parameters the server received.
  final GraphQLRequest params;

  @override
  String toString() => 'ServedRequest($method $uri)';
}
