import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_problem.dart';
import 'field_plan.dart';

/// The fields one object type collects from a selection set (spec 6.3.2
/// `CollectFields`): one [FieldPlan] per response key, in collection order.
final class PlanNode {
  /// Creates a node of [objectType]; [problem] is set when collecting failed.
  PlanNode(this.objectType, List<FieldPlan> fields, {this.problem})
    : fields = List.unmodifiable(fields);

  /// The runtime type the fields were collected for.
  final ObjectType objectType;

  /// The fields by response key, in the order they first appear.
  final List<FieldPlan> fields;

  /// Why collection stopped: an `@skip`, `@include` or `@defer` argument
  /// could not be coerced (for example a variable without a boolean). The
  /// node then has no fields and the executor reports the problem.
  final CoercionProblem? problem;
}
