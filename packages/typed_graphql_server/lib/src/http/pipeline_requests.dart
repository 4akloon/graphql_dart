import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/cost_budget.dart';
import '../server/server_request.dart';
import 'http_request_data.dart';

/// Makes the [ServerRequest] the pipeline gets for an HTTP request.
@internal
final class PipelineRequests {
  /// Creates the factory.
  const PipelineRequests();

  /// The request for [params], sent by [http], that may run the operation
  /// types in [allowedOperationTypes] and is charged to [costBudget].
  ServerRequest of(
    HttpRequestData http,
    GraphQLRequest params, {
    required Set<OperationType> allowedOperationTypes,
    CostBudget? costBudget,
  }) => ServerRequest(
    params: params,
    info: http.info,
    cancelSignal: http.cancelSignal,
    allowedOperationTypes: allowedOperationTypes,
    costBudget: costBudget,
  );
}
