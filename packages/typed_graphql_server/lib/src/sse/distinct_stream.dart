import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../http/http_request_data.dart';
import '../http/http_response_data.dart';
import '../http/pipeline_requests.dart';
import '../http/response_media_type.dart';
import '../http/result_writer.dart';
import '../server/graphql_server.dart';
import '../server/server_outcome.dart';
import '../server/server_request.dart';
import '../server/server_response.dart';
import 'event_stream.dart';

/// Answers one request as its own event stream, the distinct connections mode
/// of GraphQL over server-sent events (spec section 10).
@internal
final class DistinctStream<C> {
  /// Creates the mode over [server]: streams write a keep-alive comment every
  /// [keepAliveInterval] and refusals are written by [writer].
  const DistinctStream(this.server, this.keepAliveInterval, this.writer);

  /// The pipeline.
  final GraphQLServer<C> server;

  /// How long a stream may stay silent before a comment is written.
  final Duration keepAliveInterval;

  /// Writes the JSON refusals.
  final ResultWriter writer;

  /// The answer to [params], sent by [http].
  ///
  /// Every operation type is allowed, since a stream can deliver them all. A
  /// `405` and a `500` are JSON transport refusals; any other single result,
  /// a request error included, is the one `next` event of an accepted stream
  /// (protocol "Distinct connections mode"); a subscription is one `next` per
  /// result. Each stream ends with `complete`.
  Future<HttpResponseData> run(
    HttpRequestData http,
    GraphQLRequest params,
  ) async {
    final response = await server.handle(
      const PipelineRequests().of(
        http,
        params,
        allowedOperationTypes: ServerRequest.allOperationTypes,
      ),
    );
    return switch (response) {
      SingleResponse() && final single when _isRefusal(single.outcome) =>
        writer.single(single, ResponseMediaType.json),
      SingleResponse(:final payload) => _stream(
        Stream.value(payload.toJson()),
        response,
      ),
      StreamResponse(:final results) => _stream(
        results.map((result) => result.toJson()),
        response,
      ),
    };
  }

  bool _isRefusal(ServerOutcome outcome) =>
      outcome == ServerOutcome.methodNotAllowed ||
      outcome == ServerOutcome.internalError;

  HttpResponseData _stream(
    Stream<JsonValue> payloads,
    ServerResponse response,
  ) => EventStream(
    payloads,
    keepAliveInterval: keepAliveInterval,
  ).response(extraHeaders: response.headers);
}
