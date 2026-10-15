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
    if (cost.fieldCost <= maxCost && cost.typeCost <= maxCost) {
      return null;
    }
    return GraphQLError(
      const CostMessage().of(operation, cost, maxCost),
      locations: [SourceSpan(source, operation.start, operation.end).location],
      extensions: JsonObject({
        'code': JsonString(DiagnosticCode.maxCostExceeded.id),
      }),
    );
  }
}
