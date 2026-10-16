import 'dart:convert';

import 'package:meta/meta.dart';

import '../link/link_request.dart';
import '../link/request_headers.dart';
import 'transport_request.dart';

/// Writes a [LinkRequest] as the HTTP request GraphQL over HTTP describes
/// (spec section 9).
@internal
final class HttpRequestEncoder({
  /// The GraphQL endpoint.
  required final Uri uri,
  required Map<String, String> headers,

  /// Whether queries go as `GET` requests.
  required final bool usesGetForQueries,
}) {
  /// Creates an encoder; [headers] is copied with its names in lower case.
  this;

  /// The `accept` header: the GraphQL response type, then plain JSON for
  /// servers that predate it.
  static const String accept =
      'application/graphql-response+json, application/json;q=0.9';

  /// The headers the link adds to every request, names in lower case.
  final Map<String, String> headers = Map.unmodifiable({
    for (final MapEntry(:key, :value) in headers.entries)
      key.toLowerCase(): value,
  });

  /// [request] as a `GET` (a query, with [usesGetForQueries]) or a `POST`
  /// with a JSON body, aborted by [abortTrigger].
  TransportRequest encode(LinkRequest request, Future<void> abortTrigger) {
    if (usesGetForQueries && request.type == .query) {
      return _get(request, abortTrigger);
    }
    final body = utf8.encode(jsonEncode(request.body.toJson().toJson()));
    return TransportRequest(
      method: 'POST',
      uri: uri,
      headers: headersFor(request, const {'content-type': 'application/json'}),
      body: Stream.value(body),
      contentLength: body.length,
      abortTrigger: abortTrigger,
    );
  }

  /// [request] as a `GET`: its fields are query parameters, added to the
  /// endpoint's own, and the preflight header lets it pass the server's
  /// CSRF prevention.
  TransportRequest _get(LinkRequest request, Future<void> abortTrigger) {
    final body = request.body;
    return TransportRequest(
      method: 'GET',
      uri: uri.replace(
        queryParameters: {
          ...uri.queryParametersAll,
          'query': ?body.query,
          'operationName': ?body.operationName,
          if (body.variables case final variables?)
            'variables': jsonEncode(variables.toJson()),
          if (body.extensions case final extensions?)
            'extensions': jsonEncode(extensions.toJson()),
        },
      ),
      headers: headersFor(request, const {'graphql-require-preflight': 'true'}),
      abortTrigger: abortTrigger,
    );
  }

  /// The headers of [request], lowest priority first: `accept`, the
  /// [protocol] headers, the link's [headers], then every `RequestHeaders`
  /// entry of the request's context.
  Map<String, String> headersFor(
    LinkRequest request,
    Map<String, String> protocol,
  ) => {
    'accept': accept,
    ...protocol,
    ...headers,
    for (final entry in request.context.entries.whereType<RequestHeaders>())
      ...entry.values,
  };
}
