import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/plan_cache.dart';
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
}
