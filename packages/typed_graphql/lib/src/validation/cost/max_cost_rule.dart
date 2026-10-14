import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../limits/operation_subject.dart';
import '../rules/operation_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'cost_analysis.dart';
import 'cost_number.dart';

/// Limits the static cost of an operation (R3.5, R3.8, `GQL238`).
///
/// The cost is [CostAnalysis]'s field cost and type cost, computed without
/// variable values: a slicing variable counts with its default value in the
/// operation, else with [defaultListSize]. An operation is reported when
/// either cost is more than [maxCost]. The rule is opt-in: it is not one of
/// the specified rules.
///
/// {@category validation}
final class const MaxCostRule({
  /// The largest field cost and type cost an operation may have.
  required final double maxCost,

  /// The size of a list field the schema gives no size.
  final int defaultListSize = 10,
}) extends ValidationRule {
  /// Creates the rule.
  this;

  /// Throws an [ArgumentError] when [maxCost] is negative or NaN, and a
  /// [RangeError] when [defaultListSize] is negative.
  @override
  AstVisitor createVisitor(ValidationContext context) {
    if (maxCost.isNaN || maxCost < 0) {
      throw ArgumentError.value(maxCost, 'maxCost', 'must not be negative');
    }
    RangeError.checkNotNegative(defaultListSize, 'defaultListSize');
    return _MaxCost(context, maxCost, defaultListSize);
  }
}

final class _MaxCost(
  final ValidationContext context,
  final double maxCost,
  final int defaultListSize,
) extends OperationVisitor {
  @override
  void checkOperation(OperationDefinition operation) {
    final cost = CostAnalysis(
      context.schema,
      defaultListSize: defaultListSize,
    ).costOf(context.document, operation);
    if (cost.fieldCost > maxCost || cost.typeCost > maxCost) {
      context.report(
        .maxCostExceeded,
        '${OperationSubject(operation).text} has a field cost of '
        '${CostNumber(cost.fieldCost).text} and a type cost of '
        '${CostNumber(cost.typeCost).text}, more than the maximum of '
        '${CostNumber(maxCost).text}.',
        [operation],
      );
    }
  }
}
