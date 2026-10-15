import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import 'request_info.dart';

/// One request for `GraphQLServer.handle`: the GraphQL parameters the
/// transport decoded and what it knows about the request (R5.1).
///
/// {@category server}
final class ServerRequest {
  /// Creates a request.
  const ServerRequest({
    required this.params,
    required this.info,
    this.cancelSignal,
  });

  /// The query, operation name, variables and extensions.
  final GraphQLRequest params;

  /// The method, URI and headers of the request.
  final RequestInfo info;

  /// Owned by the caller, for example cancelled when the client disconnects;
  /// null when nothing cancels the request.
  final CancelSignal? cancelSignal;
}
