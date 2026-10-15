import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';
import 'class_names.dart';
import 'data_class_role.dart';
import 'field_group.dart';
import 'plan_scope.dart';
import 'plan_work.dart';
import 'planned_field.dart';
import 'selection_source.dart';

/// Plans one field of a data class, and queues the class of a composite field
/// unless a field of the same type and selection nodes already has one.
final class const FieldPlanner(
  /// The schema the field types are looked up in.
  final Schema schema,
) {
  /// Creates a planner.
  this;

  static const ClassNames _classNames = ClassNames();
  static const DartNames _dartNames = DartNames();

  /// The field [group] of the class [owner]; its class, if any, is added to
  /// [scope].
  PlannedField plan(String owner, FieldGroup group, PlanScope scope) {
    final memberName = _dartNames.memberName(
      group.responseName,
      reservedMembers: PlannedField.reservedMembers,
    );
    final type = group.definition.type;
    final named = schema.namedTypeOf(type);
    final isComposite =
        named is ObjectType || named is InterfaceType || named is UnionType;
    String? className;
    if (named != null && isComposite) {
      className = _classOf(owner, memberName, named, group, scope);
    }
    return PlannedField(
      responseName: group.responseName,
      memberName: memberName,
      type: type,
      isConditional: group.isConditional,
      definition: group.fieldName == '__typename' ? null : group.definition,
      className: className,
      node: group.nodes.first,
    );
  }

  String _classOf(
    String owner,
    String memberName,
    SchemaType named,
    FieldGroup group,
    PlanScope scope,
  ) {
    final nodes = [
      for (final node in group.nodes)
        if (node.selectionSet != null) node,
    ];
    final String? shared = scope.registry.classOf(named.name, nodes);
    if (shared != null) {
      return shared;
    }
    final String className = _classNames.nested(owner, memberName);
    scope.registry.record(named.name, nodes, className);
    scope.children.add(
      ClassWork(
        className,
        named,
        [
          for (final node in nodes)
            if (node.selectionSet case final set?) SelectionSource(set),
        ],
        DataClassRole.nested,
        ownerName: owner,
        ownerMember: memberName,
      ),
    );
    return className;
  }
}
