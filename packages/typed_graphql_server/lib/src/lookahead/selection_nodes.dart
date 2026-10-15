import '../plan/field_plan.dart';
import '../plan/plan_node.dart';
import 'identity_key.dart';
import 'look_ahead_budget.dart';

/// Finds the plan nodes a field's sub-selection is collected into: one per
/// object type the field's value can have (R4.18).
final class SelectionNodes {
  /// Creates the finder.
  const SelectionNodes();

  /// The nodes of the sub-selections of [plans], in plan order and, within a
  /// plan, in possible-type order; only the object type called [typeName]
  /// when it is given. A field of a leaf type has none.
  ///
  /// Plans of different parent types share their field nodes, so a node is
  /// listed once per (field nodes, object type): an interface with five
  /// implementations costs five nodes per level, not five to the depth.
  /// Each visit is charged to [budget].
  List<PlanNode> of(
    List<FieldPlan> plans,
    String? typeName,
    LookAheadBudget budget,
  ) {
    final nodes = <PlanNode>[];
    final seen = <IdentityKey>{};
    for (final plan in plans) {
      final declared = plan.field;
      if (declared == null) {
        continue;
      }
      final schema = plan.context.schema;
      final named = schema.namedTypeOf(declared.type);
      if (named == null || !named.isCompositeType) {
        continue;
      }
      for (final type in schema.possibleTypes(named)) {
        budget.charge(1);
        if (typeName != null && type.name != typeName) {
          continue;
        }
        if (seen.add(IdentityKey([type.name, ...plan.nodes]))) {
          nodes.add(plan.childFor(type));
        }
      }
    }
    return nodes;
  }
}
