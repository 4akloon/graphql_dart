import 'cost_number.dart';

/// The static cost of one operation by the IBM cost directives draft.
///
/// Both numbers are upper bounds computed before execution; `CostAnalysis`
/// defines them.
///
/// {@category validation}
final class const OperationCost(
  /// The cost of resolving the fields: each field's weight and arguments,
  /// multiplied by the sizes of the lists above it.
  final double fieldCost,

  /// The cost of the objects the operation can return: the type weights of
  /// the selected fields, multiplied by the sizes of the lists above them.
  final double typeCost,
) {
  /// Creates a cost.
  this;

  @override
  bool operator ==(Object other) =>
      other is OperationCost &&
      other.fieldCost == fieldCost &&
      other.typeCost == typeCost;

  @override
  int get hashCode => Object.hash(fieldCost, typeCost);

  @override
  String toString() =>
      'OperationCost(fieldCost: ${CostNumber(fieldCost).text}, '
      'typeCost: ${CostNumber(typeCost).text})';
}
