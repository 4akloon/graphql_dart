import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/operation_plan.dart';
import 'error_behavior.dart';
import 'error_reporter.dart';
import 'execution_limits.dart';
import 'execution_options.dart';
import 'field_execution.dart';
import 'leaf_completion.dart';
import 'list_completion.dart';
import 'object_completion.dart';
import 'response_path.dart';
import 'run_cancellation.dart';
import 'schema_bindings.dart';
import 'selection_executor.dart';
import 'value_completion.dart';

/// The state of one execution and its collaborators (spec 6): what the
/// request asked for, the coerced variables, the errors so far. One per
/// call of `ExecutableSchema.execute`; it is never shared.
final class ExecutionRun {
  /// Prepares the execution of [plan] against [schema].
  ExecutionRun({
    required this.plan,
    required this.bindings,
    required this.schema,
    required this.context,
    required this.variables,
    required this.rawVariables,
    required this.options,
    this.cancellation,
  }) : reporter = ErrorReporter(options);

  /// The operation to run.
  final OperationPlan plan;

  /// The Dart definitions behind the schema.
  final SchemaBindings bindings;

  /// The schema being executed.
  final ValidSchema schema;

  /// The context value every resolver receives.
  final Object? context;

  /// The coerced variables by name.
  final Map<String, Object?> variables;

  /// The variables as the request sent them.
  final JsonObject rawVariables;

  /// The settings of the call.
  final ExecutionOptions options;

  /// The signal and timer of the call, null when it has neither.
  final RunCancellation? cancellation;

  /// Whether the call was cancelled or timed out.
  bool get isCancelled => cancellation?.isCancelled ?? false;

  /// Makes and records the errors.
  final ErrorReporter reporter;

  // The collaborators below read the run, so they are made on first use,
  // after the run exists.

  /// Counts steps and depth.
  late final ExecutionLimits limits = ExecutionLimits(options, reporter);

  /// Runs the fields of a selection.
  late final SelectionExecutor selection = SelectionExecutor(this);

  /// Resolves and completes one field.
  late final FieldExecution fields = FieldExecution(this);

  /// Completes a value by its type.
  late final ValueCompletion values = ValueCompletion(this);

  /// Completes the value of a scalar or enum.
  late final LeafCompletion leaves = LeafCompletion(this);

  /// Completes the items of a list.
  late final ListCompletion lists = ListCompletion(this);

  /// Completes the value of an object, interface or union.
  late final ObjectCompletion objects = ObjectCompletion(this);

  /// The same execution with a fresh error log: what each event of a
  /// subscription runs in (spec 10).
  ExecutionRun restarted() => ExecutionRun(
    plan: plan,
    bindings: bindings,
    schema: schema,
    context: context,
    variables: variables,
    rawVariables: rawVariables,
    options: options,
    cancellation: cancellation,
  );

  /// Executes the operation's root selection on [rootValue] and builds the
  /// response (September2025 6.2 "Executing Operations"). A mutation runs
  /// its root fields serially.
  FutureOr<ExecutionResult> executeRoot(Object? rootValue) {
    if (cancellation case final cancelled? when cancelled.isCancelled) {
      return cancelled.result;
    }
    final root = plan.rootFor(plan.keyFor(variables));
    if (root.problem case final problem?) {
      reporter.problem(problem, null, const []);
      return _response(null);
    }
    final data = plan.operation.operation == OperationType.mutation
        ? selection.executeSerially(rootValue, root, ResponsePath.root, 1)
        : selection.execute(rootValue, root, ResponsePath.root, 1);
    if (data is! Future<JsonObject?>) {
      return _response(data);
    }
    final response = data.then(_response);
    return cancellation?.race(response) ?? response;
  }

  // A call cancelled meanwhile answers with the cancellation only (spec 13).
  ExecutionResult _response(JsonObject? data) {
    if (cancellation case final cancelled? when cancelled.isCancelled) {
      return cancelled.result;
    }
    final log = reporter.log;
    if (log.haltError case final halted?) {
      return ExecutionResult(null, errors: [halted]);
    }
    return ExecutionResult(data, errors: log.errors);
  }

  /// A completed value at a position of type [type], after the position's
  /// own rule for failure (spec 6.4.4): a failed value (Dart `null`) becomes
  /// `null` in the response unless the position is non-null and errors
  /// propagate, when it stays the failure.
  FutureOr<JsonValue?> settle(TypeRef type, FutureOr<JsonValue?> completed) =>
      completed is Future<JsonValue?>
      ? completed.then((value) => _settled(type, value))
      : _settled(type, completed);

  JsonValue? _settled(TypeRef type, JsonValue? value) {
    if (value != null) {
      return value;
    }
    final propagates =
        options.errorBehavior == ErrorBehavior.propagate && type is NonNullType;
    return propagates ? null : const JsonNull();
  }
}
