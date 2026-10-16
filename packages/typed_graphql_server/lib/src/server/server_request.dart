import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import 'cost_budget.dart';
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
    this.allowedOperationTypes = allOperationTypes,
    this.costBudget,
  });

  /// The three operation types: what a request allows by default.
  static const Set<OperationType> allOperationTypes = {
    OperationType.query,
    OperationType.mutation,
    OperationType.subscription,
  };

  /// The query, operation name, variables and extensions.
  final GraphQLRequest params;

  /// The method, URI and headers of the request.
  final RequestInfo info;

  /// Owned by the caller, for example cancelled when the client disconnects;
  /// null when nothing cancels the request.
  final CancelSignal? cancelSignal;

  /// The operation types the request may run; another type is refused with
  /// `GQL431` before the context is built.
  ///
  /// A transport that cannot deliver a type narrows it: plain JSON cannot
  /// stream a subscription, and an item of a batch should not mutate.
  final Set<OperationType> allowedOperationTypes;

  /// The budget the request's cost is charged to, shared with other requests;
  /// null charges nothing.
  final CostBudget? costBudget;
}
