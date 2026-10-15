import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../execution/error_hook.dart';
import '../execution/executable_schema.dart';
import '../execution/execution_options.dart';
import '../subscription/subscription_result.dart';
import 'execution_request.dart';
import 'server_outcome.dart';
import 'server_profile.dart';
import 'server_response.dart';

/// The core step of the execution phase: runs the operation with the
/// options of the request and maps the result to a response.
@internal
final class ExecutionStep<C> {
  /// Creates the step for [schema] under [profile], passing [onError] on.
  const ExecutionStep(this.schema, this.profile, this.onError);

  /// The schema that executes.
  final ExecutableSchema<C> schema;

  /// The profile whose settings reach the execution.
  final ServerProfile profile;

  /// The server's error hook.
  final ErrorHook? onError;

  /// The options of section 12 for a request on [source]: no timeout for a
  /// subscription, which would end a long-lived stream.
  ExecutionOptions optionsFor(
    Source source,
    OperationType? operationType,
    CancelSignal? cancelSignal,
  ) => ExecutionOptions(
    source: source,
    maskErrors: profile.maskErrors,
    onError: onError,
    includesSuggestions: profile.includesSuggestions,
    introspection: profile.introspection,
    cancelSignal: cancelSignal,
    timeout: operationType == OperationType.subscription
        ? null
        : profile.timeout,
  );

  /// Executes [request] with its options and context.
  Future<ServerResponse> run(ExecutionRequest<C> request) async {
    final params = request.request.params;
    if (request.operationType == OperationType.subscription) {
      final started = await schema.subscribe(
        request.document,
        context: request.context,
        operationName: params.operationName,
        variables: params.variables,
        options: request.options,
      );
      return switch (started) {
        SubscriptionStarted(:final results) => StreamResponse(results),
        SubscriptionRejected(:final error) => SingleResponse(
          error,
          outcome: ServerOutcome.requestError,
        ),
      };
    }
    final payload = await schema.execute(
      request.document,
      context: request.context,
      operationName: params.operationName,
      variables: params.variables,
      options: request.options,
    );
    return SingleResponse(
      payload,
      outcome: switch (payload) {
        ExecutionResult() => ServerOutcome.executed,
        RequestErrorResult() => ServerOutcome.requestError,
      },
    );
  }
}
