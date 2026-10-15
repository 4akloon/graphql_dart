import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_environment.dart';
import 'operation_plan.dart';
import 'operation_selection.dart';
import 'operation_selection_result.dart';
import 'plan_cache.dart';
import 'plan_result.dart';

/// Finds the plan of an operation: from the [PlanCache] when the same
/// `Document` object ran before, else by choosing the operation
/// (`OperationSelection`) and planning it. Only plans are cached; a request
/// error is cheap to repeat. Planning is synchronous, so two executions
/// never plan the same operation at once (R4.8).
final class OperationPlanner {
  /// Plans in [environment], remembering plans in [cache].
  const OperationPlanner(this.environment, this.cache);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// The plans made so far.
  final PlanCache cache;

  /// The plan of the operation named [operationName] in [document].
  PlanResult plan(Document document, String? operationName) {
    final known = cache.lookup(document, operationName);
    if (known != null) {
      return PlanReady(known);
    }
    final schema = environment.schema;
    switch (OperationSelection(schema).select(document, operationName)) {
      case OperationRejected(:final error):
        return PlanRejected(error);
      case OperationSelected(:final operation):
        final rootName = schema.rootTypeName(operation.operation);
        final rootType = rootName == null ? null : schema.typeNamed(rootName);
        if (rootType is! ObjectType) {
          throw StateError(
            'The root type of ${operation.operation.name} is '
            'an object type of a validated schema.',
          );
        }
        final plan = OperationPlan(
          operation,
          rootType,
          {
            for (final definition in document.definitions)
              if (definition is FragmentDefinition)
                definition.name.value: definition,
          },
          environment,
        );
        cache.store(document, operationName, plan);
        return PlanReady(plan);
    }
  }
}
