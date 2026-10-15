import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/argument_coercion.dart';
import '../coercion/coercion_result.dart';
import 'field_collector.dart';
import 'plan_context.dart';
import 'plan_node.dart';
import 'value_variables.dart';

/// What the executor does for one response key of a [PlanNode]: the field
/// nodes merged under the key, their schema field, their arguments, and the
/// nodes of the selection they carry for each runtime type, built on first
/// use and remembered (R4.8).
final class FieldPlan {
  /// Creates the plan of [fieldName] collected for [parentType].
  FieldPlan({
    required this.responseKey,
    required this.fieldName,
    required List<Field> nodes,
    required this.parentType,
    required this.field,
    required this.isDeferred,
    required this.context,
  }) : nodes = List.unmodifiable(nodes),
       _hasConstantArguments =
           field != null &&
           !const ValueVariables().occursIn(nodes.first.arguments);

  /// The key in the response: the alias, else the field name.
  final String responseKey;

  /// The name of the field.
  final String fieldName;

  /// The field nodes of the key, in document order; they agree on name and
  /// arguments, so the first one speaks for all.
  final List<Field> nodes;

  /// The object type the field was collected for.
  final ObjectType parentType;

  /// The schema field, null for `__typename` and the other meta fields.
  final SchemaField? field;

  /// Whether every field node of the key sits in a fragment with
  /// `@defer` (and an `if` that is not false). Deferred fields run inline
  /// in M5.
  final bool isDeferred;

  /// What collection reads, kept to collect the children.
  final PlanContext context;

  final bool _hasConstantArguments;
  final Map<String, PlanNode> _children = {};
  CoercionResult? _constantArguments;

  /// The node for the selection sets of [nodes] collected for the runtime
  /// type [type], the same object for the same type.
  PlanNode childFor(ObjectType type) => _children.putIfAbsent(
    type.name,
    () => FieldCollector(context).collect(type, [
      for (final node in nodes) ?node.selectionSet,
    ]),
  );

  /// The coerced arguments of the field by name (defaults included), or the
  /// problem. Arguments without variables are coerced once and remembered,
  /// except a failure caused by an error user code threw, which the caller
  /// reports each time it happens.
  CoercionResult argumentsFor(Map<String, Object?> variables) {
    final declared = field;
    if (declared == null) {
      return const CoercionSuccess(<String, Object?>{});
    }
    if (!_hasConstantArguments) {
      return _coerce(declared, variables);
    }
    final cached = _constantArguments;
    if (cached != null) {
      return cached;
    }
    final result = _coerce(declared, const {});
    if (!_hasThrown(result)) {
      _constantArguments = result;
    }
    return result;
  }

  CoercionResult _coerce(
    SchemaField declared,
    Map<String, Object?> variables,
  ) => ArgumentCoercion(context.environment).coerce(
    '${parentType.name}.$fieldName',
    declared.arguments,
    nodes.first.arguments,
    variables,
  );

  bool _hasThrown(CoercionResult result) =>
      result is CoercionFailure &&
      result.problems.any((problem) => problem.thrown != null);
}
