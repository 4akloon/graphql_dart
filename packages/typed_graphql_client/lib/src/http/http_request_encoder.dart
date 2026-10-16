import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';

import '../link/link_request.dart';
import '../link/request_headers.dart';
import '../upload/upload_files.dart';
import 'multipart_encoder.dart';
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

  /// Draws the boundaries of multipart bodies.
  required final Random random,
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

  /// [request] as a multipart `POST` (with `UploadFiles` in its context),
  /// a `GET` (a query, with [usesGetForQueries]) or a `POST` with a JSON
  /// body, aborted by [abortTrigger].
  TransportRequest encode(LinkRequest request, Future<void> abortTrigger) {
    if (request.context.entry<UploadFiles>() case final files?) {
      return _multipart(request, files, abortTrigger);
    }
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

  /// [request] with [files] as a multipart `POST`; the preflight header
  /// lets it pass the server's CSRF prevention, since a browser form can
  /// send the same content type.
  TransportRequest _multipart(
    LinkRequest request,
    UploadFiles files,
    Future<void> abortTrigger,
  ) {
    final multipart = MultipartEncoder(random).encode(request.body, files);
    return TransportRequest(
      method: 'POST',
      uri: uri,
      headers: headersFor(request, {
        'content-type': multipart.contentType,
        'graphql-require-preflight': 'true',
      }),
      body: multipart.body,
      contentLength: multipart.length,
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
