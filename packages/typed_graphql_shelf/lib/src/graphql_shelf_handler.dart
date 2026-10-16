import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'request_conversion.dart';
import 'response_conversion.dart';

/// Serves GraphQL over HTTP as a shelf `Handler` (R5.9).
///
/// It converts each shelf [Request] for a [GraphQLHttpHandler] and writes the
/// answer as a [Response]; routing, CORS and middleware stay with shelf, so
/// mount it where the endpoint lives, for example with `Router.all`.
///
/// {@category shelf}
final class GraphQLShelfHandler<C> {
  /// Creates a handler that sends requests to [server] under the limits and
  /// settings of [http].
  ///
  /// Throws an `ArgumentError` when [http] holds a limit that makes no sense.
  GraphQLShelfHandler(
    GraphQLServer<C> server, {
    HttpOptions http = const HttpOptions(),
  }) : _http = GraphQLHttpHandler<C>(server, options: http);

  final GraphQLHttpHandler<C> _http;

  /// Answers [request]; it never throws.
  FutureOr<Response> call(Request request) async => const ResponseConversion()
      .convert(await _http.handle(const RequestConversion().convert(request)));
}
