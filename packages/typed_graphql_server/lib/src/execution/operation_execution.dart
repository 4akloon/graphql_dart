import 'dart:async';

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
import 'response_path.dart';
import 'schema_bindings.dart';

/// One call of `ExecutableSchema.execute` (September2025 6.1 "Executing
/// Requests"): plans the operation, coerces the variables, runs the root
/// selection and builds the response. Request errors (no operation,
/// unusable variables) end as a `RequestErrorResult`; everything after is
/// an `ExecutionResult`.
final class OperationExecution {
  /// Prepares a call against [_schema] with [_options].
  OperationExecution(
    this._schema,
    this._bindings,
    this._planCache,
    this._options,
  );

  final ValidSchema _schema;
  final SchemaBindings _bindings;
  final PlanCache _planCache;
  final ExecutionOptions _options;

  /// Runs the operation named [operationName] of [document] with the
  /// request's [variables] and the resolvers' [context].
  FutureOr<ResponsePayload> execute(
    Document document,
    Object? context, {
    String? operationName,
    JsonObject? variables,
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
        return RequestErrorResult(errors: [error]);
      case PlanReady(:final plan):
        _checkRootValue(plan);
        return _coerceAndRun(plan, context, variables ?? JsonObject({}));
    }
  }

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

  FutureOr<ResponsePayload> _coerceAndRun(
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
        return RequestErrorResult(
          errors: _reportUnexpected(errors, unexpected),
        );
      case CoercedVariables(:final values):
        return _run(plan, context, values, variables);
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

  FutureOr<ResponsePayload> _run(
    OperationPlan plan,
    Object? context,
    Map<String, Object?> values,
    JsonObject rawVariables,
  ) {
    final run = ExecutionRun(
      plan: plan,
      bindings: _bindings,
      schema: _schema,
      context: context,
      variables: values,
      rawVariables: rawVariables,
      options: _options,
    );
    final root = plan.rootFor(plan.keyFor(values));
    if (root.problem case final problem?) {
      run.reporter.problem(problem, null, const []);
      return _response(run, null);
    }
    final rootValue = _options.rootValue;
    final data = plan.operation.operation == OperationType.mutation
        ? run.selection.executeSerially(rootValue, root, ResponsePath.root, 1)
        : run.selection.execute(rootValue, root, ResponsePath.root, 1);
    return data is Future<JsonObject?>
        ? data.then((resolved) => _response(run, resolved))
        : _response(run, data);
  }

  ExecutionResult _response(ExecutionRun run, JsonObject? data) {
    final log = run.reporter.log;
    if (log.haltError case final halted?) {
      return ExecutionResult(null, errors: [halted]);
    }
    return ExecutionResult(data, errors: log.errors);
  }
}
