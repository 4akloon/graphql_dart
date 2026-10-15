import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../lookahead/field_selection.dart';
import '../plan/field_plan.dart';
import 'execution_run.dart';
import 'response_path.dart';

/// What a resolver knows about the call it answers.
///
/// {@category execution}
final class FieldInfo {
  /// Describes the call of [fieldName] on [parentType] at [path].
  FieldInfo({
    required this.fieldName,
    required this.parentType,
    required this.returnType,
    required this.path,
    required this.fieldNodes,
    required this.operation,
    required this.variables,
    required this.schema,
    this.rootValue,
    this.plan,
    this.run,
    CancelSignal? cancelSignal,
  }) : _runSignal = cancelSignal;

  /// The field's name in the schema.
  final String fieldName;

  /// The object type the field is selected on.
  final ObjectType parentType;

  /// The field's declared type.
  final TypeRef returnType;

  /// The response path of the field, from the root.
  final ResponsePath path;

  /// The field nodes merged under the response key, in document order; do
  /// not change the list.
  final List<Field> fieldNodes;

  /// The operation being executed.
  final OperationDefinition operation;

  /// The request's variable values as sent, before coercion.
  final JsonObject variables;

  /// The schema being executed.
  final ValidSchema schema;

  /// The root value of the execution.
  final Object? rootValue;

  /// The plan of the field, which [selection] reads; the executor sets it.
  @internal
  final FieldPlan? plan;

  /// The execution that made the call, whose variables, tables and step
  /// budget [selection] reads; the executor sets it.
  @internal
  final ExecutionRun? run;

  /// The fields the request selected under this field (R4.18), for a
  /// resolver that loads only what is asked for.
  ///
  /// Built when first read, so a resolver that never reads it pays nothing
  /// (the call keeps its plan and run, no more); empty for a call made
  /// outside an execution. Reading it and walking it spend the run's step
  /// budget, see [FieldSelection].
  // `late`: the selection is built on first read, not when the call starts.
  late final FieldSelection selection = _selectionOf(plan, run);

  final CancelSignal? _runSignal;

  static FieldSelection _selectionOf(FieldPlan? plan, ExecutionRun? run) =>
      plan == null || run == null
      ? FieldSelection.empty
      : FieldSelection.under(
          [plan],
          run.variables,
          run.bindings.fields,
          run.lookAheadBudget,
        );

  /// Fires when the execution is cancelled or times out (R4.20): a resolver
  /// doing long work checks `isCancelled` or awaits `whenCancelled` to stop.
  ///
  /// It is the run's own signal, linked to the caller's and the timeout.
  /// Read it; cancelling it cancels the run. A call made outside an
  /// execution, or by one without a signal or timeout, gets a signal that
  /// is never cancelled.
  // `late`: a signal is made only for a resolver that reads it.
  late final CancelSignal cancelSignal = _runSignal ?? CancelSignal();

  /// The name of the object type the field is selected on.
  String get parentTypeName => parentType.name;
}
