import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../introspection/introspection_policy.dart';
import 'error_behavior.dart';
import 'error_hook.dart';

/// The settings of one call of `ExecutableSchema.execute`.
///
/// A pipeline builds one value per request from its configuration and the
/// request.
///
/// {@category execution}
@immutable
final class ExecutionOptions {
  /// Creates options; the defaults are the specified behaviour with masked
  /// errors.
  const ExecutionOptions({
    this.rootValue,
    this.source,
    this.errorBehavior = ErrorBehavior.propagate,
    this.maskErrors = true,
    this.onError,
    this.includesSuggestions = true,
    this.maxCoercionErrors = 50,
    this.maxDepth = 256,
    this.maxSteps = 10000000,
    this.introspection = IntrospectionPolicy.enabled,
    this.cancelSignal,
    this.timeout,
  });

  /// The parent value of the root fields; the root type's Dart type must
  /// accept it.
  final Object? rootValue;

  /// The text the document was parsed from: with it, errors carry
  /// `locations`.
  final Source? source;

  /// What a field error does to the response.
  final ErrorBehavior errorBehavior;

  /// Whether an error that is not a `GraphQLException` reaches the client as
  /// `Unexpected error.` (`GQL330`) instead of its `toString()`.
  final bool maskErrors;

  /// Sees every error user code throws, before it is recorded.
  final ErrorHook? onError;

  /// Whether input messages carry "Did you mean" text.
  final bool includesSuggestions;

  /// The most variable errors reported before "Too many errors".
  final int maxCoercionErrors;

  /// The deepest response level (fields and list levels) that completes;
  /// past it a field error (`GQL336`) ends the branch.
  final int maxDepth;

  /// The most values the execution completes; past it the execution halts
  /// (`GQL337`).
  final int maxSteps;

  /// Whether `__schema` and `__type` are answered.
  final IntrospectionPolicy introspection;

  /// Stops the execution when cancelled (spec 13). The executor only
  /// listens to it. One signal serves one request or subscription.
  final CancelSignal? cancelSignal;

  /// How long the execution (for a subscription, its whole life) may take
  /// before it is stopped with `GQL351`.
  final Duration? timeout;
}
