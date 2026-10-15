import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';
import 'applicability.dart';
import 'class_names.dart';
import 'collected_selection.dart';
import 'data_class_role.dart';
import 'field_collector.dart';
import 'field_group.dart';
import 'fragment_use.dart';
import 'plan_work.dart';
import 'planned_class.dart';
import 'planned_field.dart';
import 'planned_fragment.dart';
import 'selection_source.dart';
import 'variant_context.dart';
import 'variant_reference.dart';
import 'variant_sharing.dart';

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
      ClassWork(
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
      ClassWork(
        _classNames.fragment(fragment.name.value),
        parent,
        [SelectionSource(fragment.selectionSet)],
        DataClassRole.fragment,
      ),
    );
  }

  List<PlannedClass> _plan(ClassWork first) {
    final planned = <PlannedClass>[];
    final stack = <PlanWork>[first];
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case ReadyWork(:final plan):
          planned.add(plan);
        case final ClassWork work:
          final children = <PlanWork>[];
          final collected =
              work.variant?.collected ??
              _collector.collect(work.parent, work.sources);
          final reached = work.variant == null
              ? _reached(work.parent, collected)
              : const <ObjectType>[];
          planned.add(
            reached.isEmpty
                ? _dataClass(work, collected, children)
                : _polymorphic(work, collected, reached, children),
          );
          stack.addAll(children.reversed);
      }
    }
    return planned;
  }

  /// The object types the narrowings of an abstract [parent] reach, in
  /// possible-types order.
  List<ObjectType> _reached(SchemaType parent, CollectedSelection collected) {
    if (parent is! InterfaceType && parent is! UnionType) {
      return const [];
    }
    final reached = <ObjectType>{
      for (final narrowing in collected.narrowings)
        ...Applicability(schema).reach(narrowing.typeCondition, parent),
    };
    return [
      for (final type in schema.possibleTypes(parent))
        if (reached.contains(type)) type,
    ];
  }

  /// Plans the sealed base of [work] and queues its variants, in the order
  /// they are emitted: shared field classes, the shared holder, each
  /// variant, then the unknown one.
  PolymorphicBasePlan _polymorphic(
    ClassWork work,
    CollectedSelection collected,
    List<ObjectType> reached,
    List<PlanWork> children,
  ) {
    final collections = [
      for (final type in reached) _collector.collect(type, work.sources),
    ];
    final sharing = VariantSharing(collected, collections);
    final shared = <String, PlannedField>{
      for (final group in collected.fields)
        if (sharing.sharedFields.contains(group.responseName))
          group.responseName: _field(work.name, group, children),
    };
    final holderName = sharing.hasSharedHolder
        ? _ownHolder(work.name, collected.fragments, children)
        : null;
    final contexts = [
      for (final selection in [...collections, collected])
        VariantContext(work.name, selection, shared, holderName),
    ];
    final variants = _queueVariants(work, reached, contexts, children);
    final unknownName = _classNames.unknownVariant(work.name);
    children.add(
      _variantWork(work, unknownName, work.parent, contexts.last),
    );
    return PolymorphicBasePlan(
      name: work.name,
      role: work.role,
      typeName: work.parent.name,
      sharedFields: shared.values.toList(),
      variants: variants,
      unknownName: unknownName,
      holderName: holderName,
      ownerName: work.ownerName,
      ownerMember: work.ownerMember,
    );
  }

  /// Queues a class per reached type, each with its context in [contexts].
  List<VariantReference> _queueVariants(
    ClassWork base,
    List<ObjectType> reached,
    List<VariantContext> contexts,
    List<PlanWork> children,
  ) {
    final variants = <VariantReference>[];
    for (final (index, type) in reached.indexed) {
      final name = _classNames.variant(base.name, type.name);
      variants.add(VariantReference(type.name, name));
      children.add(_variantWork(base, name, type, contexts[index]));
    }
    return variants;
  }

  /// The work for a variant of [base]: the unknown one when [parent] is the
  /// base's own abstract type.
  ClassWork _variantWork(
    ClassWork base,
    String name,
    SchemaType parent,
    VariantContext context,
  ) => ClassWork(
    name,
    parent,
    base.sources,
    identical(parent, base.parent)
        ? DataClassRole.unknownVariant
        : DataClassRole.variant,
    variant: context,
  );

  FragmentHolderPlan _holder(
    String name,
    String ownerName,
    List<FragmentUse> uses,
  ) => FragmentHolderPlan(
    name: name,
    ownerName: ownerName,
    fragments: [for (final use in uses) PlannedFragment(use)],
  );

  /// Queues a holder class named after [owner] and returns its name; null
  /// when [uses] is empty.
  String? _ownHolder(
    String owner,
    List<FragmentUse> uses,
    List<PlanWork> children,
  ) {
    if (uses.isEmpty) {
      return null;
    }
    final name = _classNames.holder(owner);
    children.add(ReadyWork(_holder(name, owner, uses)));
    return name;
  }

  /// Plans [work] and adds the work under it to [children], in the order
  /// it is emitted: field classes, then the holder.
  DataClassPlan _dataClass(
    ClassWork work,
    CollectedSelection collected,
    List<PlanWork> children,
  ) {
    final variant = work.variant;
    final fields = <PlannedField>[
      // A polymorphic class has `typename` whether or not it was selected.
      if (collected.selectsTypename && variant == null)
        const PlannedField(
          responseName: '__typename',
          memberName: 'typename',
          type: _typenameType,
          isConditional: false,
        ),
    ];
    for (final group in collected.fields) {
      final base = variant?.sharedFields[group.responseName];
      fields.add(base?.overriding() ?? _field(work.name, group, children));
    }
    final sharedHolder = variant?.sharedHolderName;
    final holderName =
        sharedHolder ?? _ownHolder(work.name, collected.fragments, children);
    return DataClassPlan(
      name: work.name,
      role: work.role,
      typeName: work.parent.name,
      fields: fields,
      holderName: holderName,
      ownerName: work.ownerName,
      ownerMember: work.ownerMember,
      baseName: variant?.baseName,
      variantTypeName: work.role == DataClassRole.variant
          ? work.parent.name
          : null,
      holderOverridesBase: sharedHolder != null,
    );
  }

  PlannedField _field(String owner, FieldGroup group, List<PlanWork> children) {
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
      className = _classNames.nested(owner, memberName);
      children.add(
        ClassWork(
          className,
          named,
          [
            for (final node in group.nodes)
              if (node.selectionSet case final set?) SelectionSource(set),
          ],
          DataClassRole.nested,
          ownerName: owner,
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
      node: group.nodes.first,
    );
  }
}
