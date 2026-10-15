import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/plan_cache.dart';
import 'execution_options.dart';
import 'operation_execution.dart';
import 'schema_bindings.dart';

/// A validated schema with the resolvers behind it: what
/// `ExecutableSchemaBuilder.build` returns. `C` is the context type the
/// resolvers receive.
///
/// The SDL is `const SchemaPrinter().print(schema.schema)`.
///
/// {@category execution}
final class ExecutableSchema<C> {
  /// Creates the schema from a validated [schema] and its [bindings].
  ExecutableSchema(this.schema, this.bindings, {int planCacheSize = 1000})
    : planCache = PlanCache(planCacheSize);

  /// The validated schema.
  final ValidSchema schema;

  /// The run-time tables the executor reads; not part of the public API.
  @internal
  final SchemaBindings bindings;

  /// The operation plans made for this schema; not part of the public API.
  @internal
  final PlanCache planCache;

  /// Runs the operation named [operationName] of [document] (the only one
  /// when null) with the request's [variables].
  ///
  /// The result is an [ExecutionResult], or a [RequestErrorResult] when the
  /// operation cannot run: no such operation, no root type for its kind,
  /// unusable variables. It is a `Future` only when a resolver answered
  /// with one: a query of synchronous resolvers returns at once.
  ///
  /// [document] must have been validated against this schema's [schema]
  /// (the same object), and [ExecutionOptions.rootValue] must be accepted
  /// by the root type; either mismatch is an [ArgumentError].
  FutureOr<ResponsePayload> execute(
    ValidDocument document, {
    required C context,
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    if (!identical(document.schema, schema)) {
      throw ArgumentError.value(
        document,
        'document',
        'was validated against another schema',
      );
    }
    return OperationExecution(
      schema,
      bindings,
      planCache,
      options,
    ).execute(
      document.document,
      context,
      operationName: operationName,
      variables: variables,
    );
  }
}
