import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'cost_message.dart';
import 'server_request.dart';

/// The cost step of the pipeline (R5.4, `GQL238`): finds out whether the
/// selected operation costs more than the limit.
///
/// It runs per request, not per document, because a slicing argument given
/// as a variable gets its size from the request's variables.
@internal
final class CostLimit {
  /// Creates the step refusing more than [maxCost] on [analysis]'s costs.
  const CostLimit(this.analysis, this.maxCost);

  /// Computes the costs.
  final CostAnalysis analysis;

  /// The highest field cost and type cost allowed.
  final double maxCost;

  /// The refusal for [operation] of [document] (written in [source]) as
  /// [request] runs it, or null when it is within the limit.
  ///
  /// A request within the limit alone is then checked against, and charged
  /// to, the budget it shares with other requests; a refused request is never
  /// charged.
  GraphQLError? violation(
    Document document,
    Source source,
    OperationDefinition operation,
    ServerRequest request,
  ) {
    final cost = analysis.costOf(
      document,
      operation,
      variables: request.params.variables?.fields ?? const {},
    );
    // Written as a negated `<=` so that a NaN could never pass the limit.
    final isWithinAlone = cost.fieldCost <= maxCost && cost.typeCost <= maxCost;
    if (!isWithinAlone) {
      return _error(
        DiagnosticCode.maxCostExceeded,
        const CostMessage().of(operation, cost, maxCost),
        source,
        operation,
      );
    }
    final budget = request.costBudget;
    if (budget == null) return null;
    if (!budget.admits(cost, maxCost)) {
      return _error(
        DiagnosticCode.batchCostExceeded,
        const CostMessage().ofBatch(operation, cost, budget, maxCost),
        source,
        operation,
      );
    }
    budget.charge(cost);
    return null;
  }

  GraphQLError _error(
    DiagnosticCode code,
    String message,
    Source source,
    OperationDefinition operation,
  ) => GraphQLError(
    message,
    locations: [SourceSpan(source, operation.start, operation.end).location],
    extensions: JsonObject({'code': JsonString(code.id)}),
  );
}
