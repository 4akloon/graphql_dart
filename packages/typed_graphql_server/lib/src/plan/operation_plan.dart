import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_environment.dart';
import 'condition_key.dart';
import 'condition_variables.dart';
import 'field_collector.dart';
import 'lru_map.dart';
import 'plan_context.dart';
import 'plan_node.dart';

/// Everything about one operation of one document that does not depend on
/// the request's variables, except through a few booleans (spec section 5,
/// R4.8): the operation, its root type, the fragments, the variables that
/// `@skip`, `@include` and `@defer` read, and the plan nodes collected for
/// each [ConditionKey] seen.
///
/// A plan changes only by adding memoised nodes, which depend on nothing but
/// the key, so executions may share one.
final class OperationPlan {
  /// Plans [operation] of a document whose fragments are [fragments].
  OperationPlan(
    this.operation,
    this.rootType,
    Map<String, FragmentDefinition> fragments,
    this.environment,
  ) : fragments = Map.unmodifiable(fragments),
      conditionVariables = const ConditionVariables().find(
        operation,
        fragments,
      );

  /// How many [ConditionKey]s a plan remembers the root node of.
  static const int maxConditionKeys = 16;

  /// The operation to run.
  final OperationDefinition operation;

  /// The root type of the operation's type.
  final ObjectType rootType;

  /// The fragment definitions of the document by name.
  final Map<String, FragmentDefinition> fragments;

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// The names of the variables that decide which fields are collected, in
  /// the order their booleans appear in a [ConditionKey].
  final List<String> conditionVariables;

  final LruMap<ConditionKey, PlanNode> _roots = LruMap(maxConditionKeys);

  /// The key of a request whose coerced variables are [variables].
  ConditionKey keyFor(Map<String, Object?> variables) => ConditionKey([
    for (final name in conditionVariables)
      switch (variables[name]) {
        final bool value => value,
        _ => null,
      },
  ]);

  /// The fields of the operation's root selection for [key]: the same node
  /// for equal keys while the plan remembers them.
  PlanNode rootFor(ConditionKey key) {
    final known = _roots.use(key);
    if (known != null) {
      return known;
    }
    final conditionValues = <String, Object?>{
      for (var i = 0; i < conditionVariables.length; i++)
        if (key.values[i] case final bool value) conditionVariables[i]: value,
    };
    final node = FieldCollector(
      PlanContext(environment, fragments, conditionValues),
    ).collect(rootType, [operation.selectionSet]);
    _roots.store(key, node);
    return node;
  }
}
