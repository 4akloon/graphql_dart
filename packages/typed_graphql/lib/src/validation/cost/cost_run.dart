import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/value.dart';
import '../../protocol/json_value.dart';
import '../../schema/schema.dart';
import 'cost_walk.dart';
import 'cost_weights.dart';
import 'list_sizes.dart';
import 'operation_cost.dart';

/// The costs of the operations of one document: the fragment map and the
/// [CostWeights] are built once, so a document of 100000 operations does
/// not copy its definitions once per operation.
///
/// [spend], when given, charges each selection walked to a step budget; the
/// cost is then partial once it returns false, and the caller drops it.
final class CostRun(
  final Schema schema,
  final Document document,
  final int defaultListSize, {
  final bool Function(int steps)? spend,
}) {
  /// Creates the run over [document].
  this;

  final CostWeights _weights = CostWeights(schema);
  late final Map<String, FragmentDefinition> _fragments = {
    for (final definition in document.definitions)
      if (definition case FragmentDefinition(:final name))
        name.value: definition,
  };

  /// The cost of [operation] given the values of its [variables].
  OperationCost costOf(
    OperationDefinition operation, {
    Map<String, JsonValue> variables = const {},
  }) {
    final walk = CostWalk(
      schema,
      _weights,
      ListSizes(_weights, defaultListSize, variables, _defaults(operation)),
      _fragments,
      spend: spend,
    );
    final (:fieldCost, :typeCost) = walk.cost(operation);
    return OperationCost(fieldCost, typeCost);
  }

  Map<String, Value> _defaults(OperationDefinition operation) => {
    for (final definition in operation.variableDefinitions)
      definition.variable.name.value: ?definition.defaultValue,
  };
}
