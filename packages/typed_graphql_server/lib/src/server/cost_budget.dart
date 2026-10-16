import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// The cost spent so far by the requests that share one cost limit, such as
/// the items of an HTTP batch (R5.14).
///
/// Give the same budget to the `ServerRequest`s that must stay under one
/// `maxCost` together; a request charges it only when it is within the limit
/// alone and with what the others spent.
///
/// {@category server}
final class CostBudget {
  /// Creates an empty budget.
  CostBudget();

  double _fieldCost = 0;
  double _typeCost = 0;

  /// The field cost of the requests charged so far.
  double get fieldCost => _fieldCost;

  /// The type cost of the requests charged so far.
  double get typeCost => _typeCost;

  /// Whether [cost] added to what was spent keeps both sums within
  /// [maxCost].
  @internal
  bool admits(OperationCost cost, double maxCost) =>
      // Written as `<=` so that a NaN never passes.
      _fieldCost + cost.fieldCost <= maxCost &&
      _typeCost + cost.typeCost <= maxCost;

  /// Adds [cost] to what was spent.
  @internal
  void charge(OperationCost cost) {
    _fieldCost += cost.fieldCost;
    _typeCost += cost.typeCost;
  }
}
