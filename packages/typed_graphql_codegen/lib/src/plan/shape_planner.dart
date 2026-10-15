import 'dart:collection';

import 'package:typed_graphql/typed_graphql.dart';

import 'applicability.dart';
import 'class_names.dart';
import 'class_registry.dart';
import 'collected_selection.dart';
import 'data_class_role.dart';
import 'field_collector.dart';
import 'field_planner.dart';
import 'fragment_use.dart';
import 'plan_scope.dart';
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
    : _collector = FieldCollector(schema, fragments),
      _fieldPlanner = FieldPlanner(schema);

  static const ClassNames _classNames = ClassNames();
  static const TypeRef _typenameType = NonNullType(NamedType(Name('String')));

  /// The schema the selections are on.
  final Schema schema;

  /// The project's fragment definitions, by name.
  final Map<String, FragmentDefinition> fragments;

  final FieldCollector _collector;
  final FieldPlanner _fieldPlanner;

  // Each definition is planned once, whoever asks (name check, emission).
  final Map<ExecutableDefinition, List<PlannedClass>?> _plans =
      HashMap<ExecutableDefinition, List<PlannedClass>?>.identity();

  /// The most classes one operation or fragment may generate; a selection
  /// that needs more is reported as `GQL511` instead of planned.
  static const int maxClasses = 10000;

  /// Whether the plan of [definition] was cut off at [maxClasses]: it is
  /// planned, and empty, once something asked for it.
  bool exceedsLimit(ExecutableDefinition definition) =>
      _plans.containsKey(definition) && _plans[definition] == null;

  /// The classes of [operation]: its data class, then everything under it.
  /// Empty when the schema has no root for the operation type, or when the
  /// operation needs more than [maxClasses] ([exceedsLimit]).
  List<PlannedClass> planOperation(OperationDefinition operation) {
    if (_plans.containsKey(operation)) {
      return _plans[operation] ?? const [];
    }
    final rootName = schema.rootTypeName(operation.operation);
    final root = rootName == null ? null : schema.typeNamed(rootName);
    if (root == null) {
      return const [];
    }
    return _remember(
      operation,
      ClassWork(
        _classNames.operationData(operation.name?.value ?? ''),
        root,
        [SelectionSource(operation.selectionSet)],
        DataClassRole.operationData,
      ),
    );
  }

  /// The classes of [fragment]: its class, then everything under it.
  /// Empty when its type condition is unknown, or when the fragment needs
  /// more than [maxClasses] ([exceedsLimit]).
  List<PlannedClass> planFragment(FragmentDefinition fragment) {
    if (_plans.containsKey(fragment)) {
      return _plans[fragment] ?? const [];
    }
    final parent = schema.typeNamed(fragment.typeCondition.name.value);
    if (parent == null) {
      return const [];
    }
    return _remember(
      fragment,
      ClassWork(
        _classNames.fragment(fragment.name.value),
        parent,
        [SelectionSource(fragment.selectionSet)],
        DataClassRole.fragment,
      ),
    );
  }

  List<PlannedClass> _remember(
    ExecutableDefinition definition,
    ClassWork first,
  ) {
    final plan = _plan(first);
    _plans[definition] = plan;
    return plan ?? const [];
  }

  // Null when the selection needs more than [maxClasses] classes.
  List<PlannedClass>? _plan(ClassWork first) {
    final planned = <PlannedClass>[];
    final registry = ClassRegistry();
    final stack = <PlanWork>[first];
    while (stack.isNotEmpty) {
      if (planned.length >= maxClasses) {
        return null;
      }
      switch (stack.removeLast()) {
        case ReadyWork(:final plan):
          planned.add(plan);
        case final ClassWork work:
          final scope = PlanScope(registry);
          final collected =
              work.variant?.collected ??
              _collector.collect(work.parent, work.sources);
          final reached = work.variant == null
              ? Applicability(
                  schema,
                ).reachedBy(work.parent, collected.narrowings)
              : const <ObjectType>[];
          planned.add(
            reached.isEmpty
                ? _dataClass(work, collected, scope)
                : _polymorphic(work, collected, reached, scope),
          );
          stack.addAll(scope.children.reversed);
      }
    }
    return planned;
  }

  /// Plans the sealed base of [work] and queues its variants, in the order
  /// they are emitted: shared field classes, the shared holder, each
  /// variant, then the unknown one.
  PolymorphicBasePlan _polymorphic(
    ClassWork work,
    CollectedSelection collected,
    List<ObjectType> reached,
    PlanScope scope,
  ) {
    final collections = [
      for (final type in reached) _collector.collect(type, work.sources),
    ];
    final sharing = VariantSharing(collected, collections);
    final shared = <String, PlannedField>{
      for (final group in collected.fields)
        if (sharing.sharedFields.contains(group.responseName))
          group.responseName: _fieldPlanner.plan(work.name, group, scope),
    };
    final holderName = sharing.hasSharedHolder
        ? _ownHolder(work.name, collected.fragments, scope)
        : null;
    final contexts = [
      for (final selection in [...collections, collected])
        VariantContext(work.name, selection, shared, holderName),
    ];
    final variants = _queueVariants(work, reached, contexts, scope);
    final unknownName = _classNames.unknownVariant(work.name);
    scope.children.add(
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
    PlanScope scope,
  ) {
    final variants = <VariantReference>[];
    for (final (index, type) in reached.indexed) {
      final name = _classNames.variant(base.name, type.name);
      variants.add(VariantReference(type.name, name));
      scope.children.add(_variantWork(base, name, type, contexts[index]));
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
    PlanScope scope,
  ) {
    if (uses.isEmpty) {
      return null;
    }
    final name = _classNames.holder(owner);
    scope.children.add(ReadyWork(_holder(name, owner, uses)));
    return name;
  }

  List<PlannedField> _fields(
    ClassWork work,
    CollectedSelection collected,
    PlanScope scope,
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
      // A variant reads its `typename` from the class itself.
      if (variant != null && group.responseName == '__typename') continue;
      final base = variant?.sharedFields[group.responseName];
      fields.add(
        base?.overriding() ?? _fieldPlanner.plan(work.name, group, scope),
      );
    }
    return fields;
  }

  /// Plans [work] and adds the work under it to [scope], in the order
  /// it is emitted: field classes, then the holder.
  DataClassPlan _dataClass(
    ClassWork work,
    CollectedSelection collected,
    PlanScope scope,
  ) {
    final variant = work.variant;
    final fields = _fields(work, collected, scope);
    final sharedHolder = variant?.sharedHolderName;
    final holderName =
        sharedHolder ?? _ownHolder(work.name, collected.fragments, scope);
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
}
