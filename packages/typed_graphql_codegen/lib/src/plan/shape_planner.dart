import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';
import 'class_names.dart';
import 'data_class_role.dart';
import 'field_collector.dart';
import 'field_group.dart';
import 'planned_class.dart';
import 'planned_field.dart';
import 'planned_fragment.dart';
import 'selection_source.dart';

/// Plans the classes of an operation or a fragment definition, in emission
/// order, with one work stack and no recursion (spec §6).
final class ShapePlanner {
  /// Creates a planner for [schema] and the project's [fragments] by name.
  ShapePlanner(this.schema, this.fragments)
    : _collector = FieldCollector(schema, fragments);

  static const ClassNames _classNames = ClassNames();
  static const DartNames _dartNames = DartNames();
  static const TypeRef _typenameType = NonNullType(NamedType(Name('String')));

  /// The schema the selections are on.
  final Schema schema;

  /// The project's fragment definitions, by name.
  final Map<String, FragmentDefinition> fragments;

  final FieldCollector _collector;

  /// The classes of [operation]: its data class, then everything under it.
  /// Empty when the schema has no root for the operation type.
  List<PlannedClass> planOperation(OperationDefinition operation) {
    final rootName = schema.rootTypeName(operation.operation);
    final root = rootName == null ? null : schema.typeNamed(rootName);
    if (root == null) {
      return const [];
    }
    return _plan(
      _ClassWork(
        _classNames.operationData(operation.name?.value ?? ''),
        root,
        [SelectionSource(operation.selectionSet)],
        DataClassRole.operationData,
      ),
    );
  }

  /// The classes of [fragment]: its class, then everything under it.
  /// Empty when its type condition is unknown.
  List<PlannedClass> planFragment(FragmentDefinition fragment) {
    final parent = schema.typeNamed(fragment.typeCondition.name.value);
    if (parent == null) {
      return const [];
    }
    return _plan(
      _ClassWork(
        _classNames.fragment(fragment.name.value),
        parent,
        [SelectionSource(fragment.selectionSet)],
        DataClassRole.fragment,
      ),
    );
  }

  List<PlannedClass> _plan(_ClassWork first) {
    final planned = <PlannedClass>[];
    final stack = <_Work>[first];
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case _Ready(:final plan):
          planned.add(plan);
        case final _ClassWork work:
          final children = <_Work>[];
          planned.add(_dataClass(work, children));
          stack.addAll(children.reversed);
      }
    }
    return planned;
  }

  /// Plans [work] and adds the work under it to [children], in the order
  /// it is emitted: field classes, then the holder.
  DataClassPlan _dataClass(_ClassWork work, List<_Work> children) {
    final collected = _collector.collect(work.parent, work.sources);
    final fields = <PlannedField>[
      if (collected.selectsTypename)
        const PlannedField(
          responseName: '__typename',
          memberName: 'typename',
          type: _typenameType,
          isConditional: false,
        ),
    ];
    for (final group in collected.fields) {
      fields.add(_field(work, group, children));
    }
    String? holderName;
    if (collected.fragments.isNotEmpty) {
      holderName = _classNames.holder(work.name);
      children.add(
        _Ready(
          FragmentHolderPlan(
            name: holderName,
            ownerName: work.name,
            fragments: [
              for (final use in collected.fragments) PlannedFragment(use),
            ],
          ),
        ),
      );
    }
    return DataClassPlan(
      name: work.name,
      role: work.role,
      typeName: work.parent.name,
      fields: fields,
      holderName: holderName,
      ownerName: work.ownerName,
      ownerMember: work.ownerMember,
    );
  }

  PlannedField _field(_ClassWork work, FieldGroup group, List<_Work> children) {
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
      className = _classNames.nested(work.name, memberName);
      children.add(
        _ClassWork(
          className,
          named,
          [
            for (final node in group.nodes)
              if (node.selectionSet case final set?) SelectionSource(set),
          ],
          DataClassRole.nested,
          ownerName: work.name,
          ownerMember: memberName,
        ),
      );
    }
    return PlannedField(
      responseName: group.responseName,
      memberName: memberName,
      type: type,
      isConditional: group.isConditional,
      definition: group.fieldName == '__typename' ? null : group.definition,
      className: className,
    );
  }
}

sealed class _Work {
  const _Work();
}

final class _Ready extends _Work {
  const _Ready(this.plan);

  final PlannedClass plan;
}

final class _ClassWork extends _Work {
  const _ClassWork(
    this.name,
    this.parent,
    this.sources,
    this.role, {
    this.ownerName,
    this.ownerMember,
  });

  final String name;
  final SchemaType parent;
  final List<SelectionSource> sources;
  final DataClassRole role;
  final String? ownerName;
  final String? ownerMember;
}
