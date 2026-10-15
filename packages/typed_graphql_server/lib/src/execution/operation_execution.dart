import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/plan_cache.dart';
import 'execution_options.dart';
import 'execution_run.dart';
import 'operation_preparation.dart';
import 'prepared_operation.dart';
import 'schema_bindings.dart';

/// One call of `ExecutableSchema.execute` (September2025 6.1 "Executing
/// Requests"): prepares the operation, runs the root selection and builds
/// the response. Request errors (no operation, unusable variables) end as a
/// `RequestErrorResult`; everything after is an `ExecutionResult`.
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
    final prepared =
        OperationPreparation(
          _schema,
          _bindings,
          _planCache,
          _options,
        ).prepare(
          document,
          context,
          operationName: operationName,
          variables: variables,
        );
    return switch (prepared) {
      OperationRefused(:final error) => error,
      OperationReady(:final run) => _run(run),
    };
  }

  // The timer and the listener end with the run, whether it finished at once
  // or later (spec 13).
  FutureOr<ExecutionResult> _run(ExecutionRun run) {
    final FutureOr<ExecutionResult> result;
    try {
      result = run.executeRoot(_options.rootValue);
    } on Object {
      run.cancellation?.dispose();
      rethrow;
    }
    final cancellation = run.cancellation;
    if (cancellation == null) {
      return result;
    }
    if (result is Future<ExecutionResult>) {
      return result.whenComplete(cancellation.dispose);
    }
    cancellation.dispose();
    return result;
  }
}
