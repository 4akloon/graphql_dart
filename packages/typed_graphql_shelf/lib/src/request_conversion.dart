import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// Turns a shelf [Request] into the [HttpRequestData] the HTTP handler reads.
@internal
final class RequestConversion {
  /// Creates the conversion.
  const RequestConversion();

  /// The data of [request].
  ///
  /// shelf lower-cases header names but joins repeated values with `,` only,
  /// so they are joined again with `, `, which is what the handler expects.
  /// The body is the request's own stream, read only when the handler needs
  /// it. No cancel signal is given: shelf does not report that the client
  /// went away, but `shelf_io` cancels the subscription to a streamed
  /// response body when it does, and that is what stops the work behind an
  /// event stream.
  HttpRequestData convert(Request request) => HttpRequestData(
    method: request.method,
    uri: request.requestedUri,
    headers: _joinedHeaders(request),
    body: request.read(),
    source: request,
  );

  /// What the graphql-ws handler reads of the upgrade [request], whose body
  /// is not touched.
  RequestInfo info(Request request) => RequestInfo(
    method: request.method,
    uri: request.requestedUri,
    headers: _joinedHeaders(request),
    source: request,
  );

  static Map<String, String> _joinedHeaders(Request request) => {
    for (final MapEntry(:key, :value) in request.headersAll.entries)
      key: value.join(', '),
  };
}
