import '../plan/field_plan.dart';
import '../plan/plan_node.dart';

/// Finds the plan nodes a field's sub-selection is collected into: one per
/// object type the field's value can have (R4.18).
final class SelectionNodes {
  /// Creates the finder.
  const SelectionNodes();

  /// The nodes of the sub-selections of [plans], in plan order and, within a
  /// plan, in possible-type order; only the object type called [typeName]
  /// when it is given. A field of a leaf type has none.
  List<PlanNode> of(List<FieldPlan> plans, String? typeName) {
    final nodes = <PlanNode>[];
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
        if (typeName == null || type.name == typeName) {
          nodes.add(plan.childFor(type));
        }
      }
    }
    return nodes;
  }
}
