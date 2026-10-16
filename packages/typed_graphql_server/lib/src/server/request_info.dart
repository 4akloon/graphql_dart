import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'header_names.dart';

/// What the transport knows about one request, besides the GraphQL
/// parameters: the context factory and the extensions read it (R5.1).
///
/// {@category server}
final class RequestInfo {
  /// Creates the information about a request.
  ///
  /// [headers] names are lower-cased. [source] is the host's own request
  /// object (for example a `shelf` request); the library never reads it.
  RequestInfo({
    required this.method,
    required this.uri,
    Map<String, String> headers = const {},
    this.source,
    this.connectionParams,
  }) : headers = const HeaderNames().lowerCased(headers);

  /// The HTTP method as the transport gave it; the pipeline compares it with
  /// `POST` ignoring case, and only `POST` may run a mutation.
  final String method;

  /// The URI the request was sent to.
  final Uri uri;

  /// The headers, unmodifiable, with lower-case names. A transport joins
  /// repeated values with `, `.
  final Map<String, String> headers;

  /// The host's own request object, never read by the library.
  final Object? source;

  /// The payload of the graphql-ws `connection_init` message of the
  /// connection the request came on, null for other transports; a context
  /// factory reads a token sent there.
  final JsonObject? connectionParams;

  /// The value of the header [name], whatever its case, or null.
  String? header(String name) => headers[name.toLowerCase()];

  /// A copy that carries [connectionParams] and, when given, another
  /// [method] and extra [headers] (the new values win); the graphql-ws
  /// transport builds the request of each of its messages from the upgrade
  /// this way.
  @internal
  RequestInfo withConnection(
    JsonObject? connectionParams, {
    String? method,
    Map<String, String> headers = const {},
  }) => RequestInfo(
    method: method ?? this.method,
    uri: uri,
    headers: {...this.headers, ...headers},
    source: source,
    connectionParams: connectionParams,
  );
}
