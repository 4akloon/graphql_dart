import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_environment.dart';
import '../coercion/input_coercion.dart';
import '../coercion/unexpected_input_error.dart';
import '../coercion/variable_coercion.dart';
import '../coercion/variable_coercion_result.dart';
import '../plan/operation_plan.dart';
import '../plan/operation_planner.dart';
import '../plan/plan_cache.dart';
import '../plan/plan_result.dart';
import 'error_reporter.dart';
import 'execution_options.dart';
import 'execution_run.dart';
import 'prepared_operation.dart';
import 'run_cancellation.dart';
import 'schema_bindings.dart';

/// The part of a request that `execute` and `subscribe` share (September2025
/// 6.1 up to "ExecuteRequest"): selects and plans the operation and coerces
/// the variables. Request errors end as an [OperationRefused].
final class OperationPreparation {
  /// Prepares calls against [_schema] with [_options].
  OperationPreparation(
    this._schema,
    this._bindings,
    this._planCache,
    this._options,
  );

  final ValidSchema _schema;
  final SchemaBindings _bindings;
  final PlanCache _planCache;
  final ExecutionOptions _options;

  /// Prepares the operation named [operationName] of [document] with the
  /// request's [variables] and the resolvers' [context]. With
  /// [isSubscription] any other kind of operation is refused (`GQL324`).
  PreparedOperation prepare(
    Document document,
    Object? context, {
    String? operationName,
    JsonObject? variables,
    bool isSubscription = false,
  }) {
    final environment = CoercionEnvironment(
      _schema.schema,
      _bindings,
      includesSuggestions: _options.includesSuggestions,
    );
    switch (OperationPlanner(
      environment,
      _planCache,
    ).plan(document, operationName)) {
      case PlanRejected(:final error):
        return OperationRefused(RequestErrorResult(errors: [error]));
      case PlanReady(:final plan):
        if (isSubscription &&
            plan.operation.operation != OperationType.subscription) {
          return OperationRefused(_notSubscription());
        }
        _checkRootValue(plan);
        return _coerce(plan, context, variables ?? JsonObject({}));
    }
  }

  RequestErrorResult _notSubscription() => RequestErrorResult(
    errors: [
      GraphQLError(
        'Expected subscription operation.',
        extensions: JsonObject({
          'code': JsonString(DiagnosticCode.subscriptionRequired.id),
        }),
      ),
    ],
  );

  void _checkRootValue(OperationPlan plan) {
    final root = _bindings.objects[plan.rootType.name];
    if (root != null && !root.accepts(_options.rootValue)) {
      throw ArgumentError.value(
        _options.rootValue,
        'rootValue',
        'is not accepted by the root type "${root.name}" '
            '(${root.dartTypeName})',
      );
    }
  }

  PreparedOperation _coerce(
    OperationPlan plan,
    Object? context,
    JsonObject variables,
  ) {
    final coercion = VariableCoercion(
      InputCoercion(
        _schema.schema,
        _bindings,
        includesSuggestions: _options.includesSuggestions,
      ),
      maxCoercionErrors: _options.maxCoercionErrors,
    );
    switch (coercion.coerce(
      plan.operation.variableDefinitions,
      variables,
      source: _options.source,
    )) {
      case VariableCoercionFailure(:final errors, :final unexpected):
        return OperationRefused(
          RequestErrorResult(errors: _reportUnexpected(errors, unexpected)),
        );
      case CoercedVariables(:final values):
        return OperationReady(
          ExecutionRun(
            plan: plan,
            bindings: _bindings,
            schema: _schema,
            context: context,
            variables: values,
            rawVariables: variables,
            options: _options,
            cancellation: RunCancellation.from(_options),
          ),
        );
    }
  }

  // The hook sees what user code threw while variables were coerced and may
  // replace the error that stands for it.
  List<GraphQLError> _reportUnexpected(
    List<GraphQLError> errors,
    List<UnexpectedInputError> unexpected,
  ) {
    final reporter = ErrorReporter(_options);
    final replacements = Map<GraphQLError, GraphQLError>.identity();
    for (final entry in unexpected) {
      replacements[entry.reported] = reporter.hooked(
        entry.error,
        entry.stackTrace,
        entry.reported,
      );
    }
    return [for (final error in errors) replacements[error] ?? error];
  }
}
