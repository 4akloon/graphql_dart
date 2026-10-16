import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../http/http_request_data.dart';
import '../http/http_response_body.dart';
import '../http/http_response_data.dart';
import '../http/pipeline_requests.dart';
import '../http/request_decoding.dart';
import '../http/response_media_type.dart';
import '../http/result_writer.dart';
import '../http/transport_errors.dart';
import '../server/graphql_server.dart';
import '../server/server_outcome.dart';
import '../server/server_request.dart';
import '../server/server_response.dart';
import 'single_connection.dart';
import 'stream_operation.dart';
import 'stream_refusals.dart';
import 'stream_reservations.dart';
import 'stream_token_reader.dart';

/// Runs the operations posted to a single-connection stream (spec section 10):
/// the `POST` is answered with `202` and the results go to the stream.
@internal
final class StreamOperations<C> {
  /// Creates the runner over [server] and the [reservations] it finds streams
  /// in; refusals are made by [errors] and request errors written by [writer].
  const StreamOperations(
    this.server,
    this.reservations,
    this.errors,
    this.writer,
  );

  /// The pipeline.
  final GraphQLServer<C> server;

  /// The streams.
  final StreamReservations reservations;

  /// Makes the JSON refusals.
  final TransportErrors errors;

  /// Writes a request error as the answer of the `POST`.
  final ResultWriter writer;

  /// The answer to a `POST` that carries a token and was decoded as
  /// [decoding].
  ///
  /// The token is looked up again because the body took time to arrive. A
  /// request error, a `405` and a `500` answer the `POST` as they do over
  /// plain JSON (protocol "Executing operations"); a result is `202`.
  Future<HttpResponseData> run(
    HttpRequestData http,
    RequestDecoding decoding,
    ResponseMediaType type,
  ) async {
    final token = const StreamTokenReader().tokenOf(http);
    final connection = token == null ? null : reservations.lookup(token);
    if (connection == null) return StreamRefusals(errors).notFound();
    return switch (decoding) {
      DecodedRequest(request: final params) => await _admit(
        connection,
        http,
        params,
        type,
      ),
      DecodedBatch() => errors.refusal(
        422,
        DiagnosticCode.batchingDisabled,
        'A batch cannot run on an event stream.',
      ),
      DecodingRefusal(:final status, :final code, :final message) =>
        errors.refusal(status, code, message),
    };
  }

  Future<HttpResponseData> _admit(
    SingleConnection connection,
    HttpRequestData http,
    GraphQLRequest params,
    ResponseMediaType type,
  ) async {
    final id = switch (params.extensions?['operationId']) {
      JsonString(:final value) when value.isNotEmpty => value,
      _ => null,
    };
    if (id == null) {
      return errors.refusal(
        400,
        DiagnosticCode.operationIdRequired,
        'A request on an event stream needs extensions.operationId.',
      );
    }
    return _refusalFor(connection, id) ??
        await _execute(connection, connection.admit(id), http, params, type);
  }

  HttpResponseData? _refusalFor(SingleConnection connection, String id) {
    if (connection.isRunning(id)) {
      return errors.refusal(
        409,
        DiagnosticCode.operationIdInUse,
        'An operation with this id is already running.',
      );
    }
    if (connection.isFull) {
      return errors.refusal(
        409,
        DiagnosticCode.tooManyStreamOperations,
        'The event stream runs too many operations.',
      );
    }
    return null;
  }

  // The id is taken before the pipeline answers, so a second `POST` with it
  // meanwhile is refused. A throw after that frees it again; the handler
  // answers `500`.
  Future<HttpResponseData> _execute(
    SingleConnection connection,
    StreamOperation operation,
    HttpRequestData http,
    GraphQLRequest params,
    ResponseMediaType type,
  ) async {
    try {
      return await _run(connection, operation, http, params, type);
    } on Object {
      connection.release(operation);
      rethrow;
    }
  }

  Future<HttpResponseData> _run(
    SingleConnection connection,
    StreamOperation operation,
    HttpRequestData http,
    GraphQLRequest params,
    ResponseMediaType type,
  ) async {
    final response = await server.handle(
      // The request's own signal belongs to a `POST` that is over once it is
      // answered; the operation lives on the stream.
      const PipelineRequests().of(
        HttpRequestData(
          method: http.method,
          uri: http.uri,
          headers: http.headers,
          source: http.source,
        ),
        params,
        allowedOperationTypes: ServerRequest.allOperationTypes,
      ),
    );
    switch (response) {
      case SingleResponse() when response.outcome == ServerOutcome.executed:
        operation.attach(Stream<JsonValue>.value(response.body));
      case SingleResponse():
        connection.release(operation);
        return writer.single(response, type);
      case StreamResponse(:final results):
        operation.attach(results.map<JsonValue>((result) => result.toJson()));
    }
    return HttpResponseData(
      202,
      headers: response.headers,
      body: const FixedBody([]),
    );
  }
}
