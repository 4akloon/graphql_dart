import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/plan_cache.dart';
import '../subscription/subscription_result.dart';
import 'execution_options.dart';
import 'execution_run.dart';
import 'operation_preparation.dart';
import 'prepared_operation.dart';
import 'schema_bindings.dart';
import 'subscription_responses.dart';

/// One call of `ExecutableSchema.subscribe` (September2025 6.2.3
/// "Subscription"): prepares the operation, creates the source event stream
/// of its single root field and maps the events to responses.
final class SubscriptionExecution {
  /// Prepares a call against [_schema] with [_options].
  SubscriptionExecution(
    this._schema,
    this._bindings,
    this._planCache,
    this._options,
  );

  final ValidSchema _schema;
  final SchemaBindings _bindings;
  final PlanCache _planCache;
  final ExecutionOptions _options;

  /// Starts the subscription [operationName] of [document].
  FutureOr<SubscriptionResult> subscribe(
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
          isSubscription: true,
        );
    return switch (prepared) {
      OperationRefused(:final error) => SubscriptionRejected(error),
      OperationReady(:final run) => _open(run),
    };
  }

  FutureOr<SubscriptionResult> _open(ExecutionRun run) {
    if (run.cancellation case final cancelled? when cancelled.isCancelled) {
      cancelled.dispose();
      return SubscriptionRejected(
        RequestErrorResult(errors: [cancelled.error]),
      );
    }
    final root = run.plan.rootFor(run.plan.keyFor(run.variables));
    final fields = root.fields;
    if (root.problem case final problem?) {
      run.reporter.problem(problem, null, const []);
    }
    if (fields.isEmpty) {
      return _rejected(run);
    }
    final opened = run.fields.openSource(_options.rootValue, fields.first);
    return opened is Future<Stream<Object?>?>
        ? opened.then((source) => _started(run, source))
        : _started(run, opened);
  }

  SubscriptionResult _started(ExecutionRun run, Stream<Object?>? source) =>
      source == null
      ? _rejected(run)
      : SubscriptionStarted(SubscriptionResponses(run, source).stream);

  // A run that found no source has errors in its log; one that found no
  // root field at all has none, so it says so.
  SubscriptionRejected _rejected(ExecutionRun run) {
    run.cancellation?.dispose();
    final log = run.reporter.log;
    final errors = switch (log.haltError) {
      final halted? => [halted],
      null => log.errors,
    };
    return SubscriptionRejected(
      RequestErrorResult(
        errors: errors.isEmpty
            ? [
                GraphQLError(
                  'The subscription selects no root field.',
                  extensions: JsonObject({
                    'code': JsonString(DiagnosticCode.noOperation.id),
                  }),
                ),
              ]
            : errors,
      ),
    );
  }
}
