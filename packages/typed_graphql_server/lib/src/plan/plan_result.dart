import 'package:typed_graphql/typed_graphql.dart';

import 'operation_plan.dart';

/// The outcome of planning a request's operation.
sealed class PlanResult {
  const PlanResult();
}

/// The plan to execute.
final class PlanReady extends PlanResult {
  /// Wraps [plan].
  const PlanReady(this.plan);

  /// The plan, possibly from the cache.
  final OperationPlan plan;
}

/// The operation cannot run; [error] is the request error.
final class PlanRejected extends PlanResult {
  /// Wraps [error].
  const PlanRejected(this.error);

  /// The request error, with its code in `extensions`.
  final GraphQLError error;
}
