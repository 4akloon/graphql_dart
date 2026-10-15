import 'package:typed_graphql/typed_graphql.dart';

import '../introspection/entry_fields.dart';
import 'field_plan.dart';
import 'plan_context.dart';

/// The field nodes collected so far under one response key.
final class FieldAccumulator {
  /// Starts with the first [node] met for the key.
  FieldAccumulator(Field node, {required this.isDeferred}) : _nodes = {node};

  // Nodes compare by identity, so a node reached twice (a fragment visited
  // again after a deferred visit) is kept once.
  final Set<Field> _nodes;

  /// Whether every node added so far is deferred (read by M14, incremental
  /// delivery, through `FieldPlan.isDeferred`).
  bool isDeferred;

  /// Adds [node]; the key stays deferred only while every node is.
  void add(Field node, {required bool isDeferred}) {
    _nodes.add(node);
    this.isDeferred = this.isDeferred && isDeferred;
  }

  /// Whether the field exists on [parentType] (or is a meta field).
  /// September2025 section 6.4 (Executing Fields) skips a field without a
  /// definition, which only a document that was not validated can name.
  bool isDefinedOn(PlanContext context, ObjectType parentType) =>
      _nodes.first.name.value == '__typename' ||
      _fieldOn(context, parentType) != null;

  // `__typename` is no schema field; `__schema` and `__type` exist on the
  // query root only.
  SchemaField? _fieldOn(PlanContext context, ObjectType parentType) =>
      const EntryFields().of(
        context.schema,
        parentType,
        _nodes.first.name.value,
      ) ??
      parentType.fieldNamed(_nodes.first.name.value);

  /// The plan of the key for [parentType].
  FieldPlan build(PlanContext context, ObjectType parentType) {
    final first = _nodes.first;
    return FieldPlan(
      responseKey: first.alias?.value ?? first.name.value,
      fieldName: first.name.value,
      nodes: _nodes.toList(),
      parentType: parentType,
      field: _fieldOn(context, parentType),
      isDeferred: isDeferred,
      context: context,
    );
  }
}
