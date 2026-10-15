import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/value.dart';
import '../../protocol/json_value.dart';
import '../../schema/schema.dart';
import 'cost_walk.dart';
import 'cost_weights.dart';
import 'list_sizes.dart';
import 'operation_cost.dart';

/// Computes the static cost of an operation by the IBM cost directives draft
/// (`@cost` and `@listSize`; R3.8).
///
/// The schema need not include the cost directives: without them every
/// weight is its default. A weight that is not a number counts as the
/// default too (the schema check reports it).
///
/// - The **type weight** of a named type is its `@cost` weight, else 1 for
///   an object and 0 for a scalar or an enum. An interface or a union weighs
///   as its heaviest possible type, the draft's upper bound. An input object
///   weighs 0.
/// - The **field weight** is the field definition's `@cost` weight, else the
///   type weight of its named return type.
/// - The **argument cost** of a field is, for each argument given, the
///   argument definition's `@cost` weight, else the type weight of its
///   named input type, plus the weight of each input field written in its
///   value (inside lists too, at any depth) the same way. A variable adds
///   nothing beyond its argument. Unknown arguments and input fields add 0.
/// - The **directive cost** of a field is the argument cost of each
///   directive applied to it.
/// - The **raw cost** of a field is its field weight plus its argument cost
///   plus its directive cost, but never below 0: a negative weight lowers
///   the cost only down to 0.
/// - The **list size** of a field whose type is a list (ignoring non-null)
///   is the largest slicing argument given: an `Int` literal, or a
///   variable's value in `variables`, else its default in the operation,
///   else `defaultListSize`; a `null` is ignored. With none given, it is
///   the largest default value of a slicing argument, else `assumedSize`,
///   else `defaultListSize`. A list field without `@listSize` has
///   `defaultListSize`; any other field has 1. When `@listSize` has
///   `sizedFields`, the field itself has size 1 and the size above is the
///   size of each child, fragments included, whose name is listed.
/// - The **field cost** of a selection set is the sum over its fields of
///   the raw cost plus the size times the field cost of the field's own
///   selection set. Inline fragments and spreads add the cost of their
///   selections to the enclosing set, an upper bound: fragments on
///   different possible types all count.
/// - The **type cost** of a selection set is the sum over its fields of the
///   size times the type weight of the field's named type plus the type
///   cost of its selection set. The operation's type cost adds its root
///   type's weight.
///
/// The meta-fields `__typename`, `__schema` and `__type` cost 0 and their
/// selections are not counted; nor are a field its parent type does not
/// define and its selections.
///
/// The cost is computed without recursion in time polynomial in the
/// document, however often fragments are spread: each fragment is walked
/// once for each distinct sizing context it is spread in (at most the
/// fragments times the contexts `sizedFields` create). Costs saturate at the
/// largest finite double, so an overflowing size is a very large cost, never
/// NaN or infinite. A fragment spread inside itself counts 0, like an
/// unknown fragment.
///
/// {@category validation}
final class const CostAnalysis(
  /// The schema the operations are written against.
  final Schema schema, {

  /// The size of a list field the schema gives no size.
  final int defaultListSize = 10,
}) {
  /// Creates the analysis of operations against [schema].
  this;

  /// The cost of [operation], an operation of [document], given the values
  /// of its [variables].
  ///
  /// Throws a [RangeError] when [defaultListSize] is negative.
  OperationCost costOf(
    Document document,
    OperationDefinition operation, {
    Map<String, JsonValue> variables = const {},
  }) {
    RangeError.checkNotNegative(defaultListSize, 'defaultListSize');
    final weights = CostWeights(schema);
    final walk = CostWalk(
      schema,
      weights,
      ListSizes(weights, defaultListSize, variables, _defaults(operation)),
      {
        for (final definition in document.definitions)
          if (definition case FragmentDefinition(:final name))
            name.value: definition,
      },
    );
    final (:fieldCost, :typeCost) = walk.cost(operation);
    return OperationCost(fieldCost, typeCost);
  }

  Map<String, Value> _defaults(OperationDefinition operation) => {
    for (final definition in operation.variableDefinitions)
      definition.variable.name.value: ?definition.defaultValue,
  };
}
