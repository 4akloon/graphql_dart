import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/graphql_server.dart';
import '../server/server_response.dart';
import 'http_request_data.dart';
import 'http_response_data.dart';
import 'pipeline_requests.dart';
import 'response_media_type.dart';
import 'result_writer.dart';
import 'transport_errors.dart';

/// Runs one decoded request through the pipeline and writes its result as
/// JSON (spec section 4, step 9).
@internal
final class JsonExchange<C> {
  /// Creates an exchange over [server] that writes with [writer].
  JsonExchange(this.server, this.writer)
    : _errors = TransportErrors(server.profile.maskErrors);

  /// The pipeline.
  final GraphQLServer<C> server;

  /// Writes a result as an HTTP response.
  final ResultWriter writer;

  final TransportErrors _errors;

  /// The operation types plain JSON can deliver: a subscription needs a
  /// stream, which only the other transports have.
  static const Set<OperationType> allowedOperationTypes = {
    OperationType.query,
    OperationType.mutation,
  };

  /// The pipeline's answer to [params], sent by [http], as a response of
  /// media type [type].
  Future<HttpResponseData> run(
    HttpRequestData http,
    GraphQLRequest params,
    ResponseMediaType type,
  ) async {
    final response = await server.handle(
      const PipelineRequests().of(
        http,
        params,
        allowedOperationTypes: allowedOperationTypes,
      ),
    );
    switch (response) {
      case SingleResponse():
        return writer.single(response, type);
      case StreamResponse(:final results):
        // Only an extension can make one; nobody will listen, so release it.
        results.listen(null).cancel().ignore();
        return _errors.unexpected(
          StateError('A stream cannot be sent as JSON.'),
        );
    }
  }
}
