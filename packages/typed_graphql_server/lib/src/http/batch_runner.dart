import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/cost_budget.dart';
import '../server/graphql_server.dart';
import '../server/server_response.dart';
import 'batch_policy.dart';
import 'failure_description.dart';
import 'http_request_data.dart';
import 'http_response_data.dart';
import 'pipeline_requests.dart';
import 'response_media_type.dart';
import 'result_writer.dart';
import 'transport_errors.dart';

/// Runs the items of a batch and writes their results as one response (spec
/// section 6).
@internal
final class BatchRunner<C> {
  /// Creates a runner over [server] that follows [policy] and writes with
  /// [writer].
  const BatchRunner(this.server, this.policy, this.writer);

  /// The pipeline.
  final GraphQLServer<C> server;

  /// The size and operation types the batch may have.
  final BatchPolicy policy;

  /// Writes the results as an HTTP response.
  final ResultWriter writer;

  TransportErrors get _errors => TransportErrors(server.profile.maskErrors);

  Set<OperationType> get _allowedOperationTypes => {
    OperationType.query,
    if (policy.allowsMutations) OperationType.mutation,
  };

  /// The response to [items], sent by [http], in media type [type].
  ///
  /// Every item is decoded before the first runs, so a malformed one refuses
  /// the batch and nothing has been executed; then the items run in order,
  /// sharing one cost budget.
  Future<HttpResponseData> run(
    HttpRequestData http,
    List<JsonValue> items,
    ResponseMediaType type,
  ) async => switch (_decode(items)) {
    DecodeFailure(:final message) => _errors.refusal(
      422,
      DiagnosticCode.malformedRequestParameters,
      message,
    ),
    DecodeSuccess(:final value) => await _runAll(http, value, type),
  };

  Future<HttpResponseData> _runAll(
    HttpRequestData http,
    List<GraphQLRequest> requests,
    ResponseMediaType type,
  ) async {
    final budget = CostBudget();
    final payloads = <ResponsePayload>[];
    for (final params in requests) {
      payloads.add(await _runItem(http, params, budget));
    }
    return writer.batch(payloads, type);
  }

  DecodeResult<List<GraphQLRequest>> _decode(List<JsonValue> items) {
    final requests = <GraphQLRequest>[];
    for (var index = 0; index < items.length; index++) {
      switch (GraphQLRequest.decode(items[index])) {
        case DecodeSuccess(:final value):
          requests.add(value);
        case DecodeFailure() && final failure:
          return DecodeFailure(
            'The request at index $index is malformed: '
            '${const FailureDescription().of(failure)}',
          );
      }
    }
    return DecodeSuccess(requests);
  }

  Future<ResponsePayload> _runItem(
    HttpRequestData http,
    GraphQLRequest params,
    CostBudget budget,
  ) async {
    final response = await server.handle(
      const PipelineRequests().of(
        http,
        params,
        allowedOperationTypes: _allowedOperationTypes,
        costBudget: budget,
      ),
    );
    switch (response) {
      case SingleResponse(:final payload):
        return payload;
      case StreamResponse(:final results):
        // Only an extension can make one; nobody will listen, so release it.
        results.listen(null).cancel().ignore();
        return RequestErrorResult(
          errors: [
            _errors.unexpectedError(
              StateError('A stream cannot be sent in a batch.'),
            ),
          ],
        );
    }
  }
}
