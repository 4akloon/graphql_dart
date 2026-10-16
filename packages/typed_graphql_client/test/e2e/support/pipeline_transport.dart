import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'request_params_reader.dart';
import 'served_request.dart';

/// An [HttpTransport] that serves each request with a [GraphQLServer], with
/// no network, and records what it served.
///
/// The status of a response is the one GraphQL over HTTP gives the
/// [ServerOutcome]: `executed` 200, `requestError` 400, `methodNotAllowed`
/// 405, `internalError` 500. M7 will own this mapping; here it is a test
/// double.
///
/// `isAuthorized` stands for the authentication layer in front of a real
/// server: the M6 context factory can only turn a refusal into a 400
/// `requestError`, so a stale token is answered here with a 401 before the
/// server runs, as a gateway would.
final class PipelineTransport implements HttpTransport {
  /// Creates a transport over [server]; [isAuthorized] receives the
  /// `authorization` header (null when absent) and, when it gives false, the
  /// request is answered with a 401 and never reaches the server.
  PipelineTransport(this.server, {this.isAuthorized});

  /// The server that answers.
  final GraphQLServer<Object?> server;

  /// Decides from the `authorization` header whether a request is served.
  final bool Function(String? authorization)? isAuthorized;

  /// Every request received, in order, including the refused ones.
  final List<ServedRequest> served = [];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final params = await const RequestParamsReader().read(request);
    served.add(
      ServedRequest(
        method: request.method,
        uri: request.uri,
        headers: request.headers,
        params: params,
      ),
    );
    if (isAuthorized?.call(request.headers['authorization']) == false) {
      return _unauthorized();
    }
    final response = await server.handle(
      ServerRequest(
        params: params,
        info: RequestInfo(
          method: request.method,
          uri: request.uri,
          headers: request.headers,
        ),
      ),
    );
    return switch (response) {
      SingleResponse() => _write(response),
      StreamResponse() => throw StateError('Streams need M7 (M11z).'),
    };
  }

  TransportResponse _write(SingleResponse response) => _answer(
    switch (response.outcome) {
      ServerOutcome.executed => 200,
      ServerOutcome.requestError => 400,
      ServerOutcome.methodNotAllowed => 405,
      ServerOutcome.internalError => 500,
    },
    response.body,
    response.headers,
  );

  TransportResponse _unauthorized() => _answer(
    401,
    JsonObject({
      'errors': JsonArray([GraphQLError('Unauthorized.').toJson()]),
    }),
    const {},
  );

  TransportResponse _answer(
    int status,
    JsonObject body,
    Map<String, String> headers,
  ) => TransportResponse(
    statusCode: status,
    headers: {...headers, 'content-type': 'application/graphql-response+json'},
    body: Stream.value(utf8.encode(jsonEncode(body.toJson()))),
  );
}
