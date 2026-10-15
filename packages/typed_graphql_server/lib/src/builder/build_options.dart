import 'package:typed_graphql/typed_graphql.dart';

import '../authorization/authorizer.dart';
import '../execution/directive_middleware.dart';
import '../execution/field_middleware.dart';

/// The settings of `ExecutableSchemaBuilder.build` besides the root types.
///
/// Grouped in one object to keep `build` within five parameters; later
/// stages add their settings here. `C` is the builder's context type.
///
/// {@category builder}
final class BuildOptions<C> {
  /// Creates the options.
  const BuildOptions({
    this.directives = const [],
    this.includesDeferAndStream = false,
    this.description,
    this.planCacheSize = 1000,
    this.middleware = const [],
    this.directiveMiddleware = const {},
    this.authorizer,
  }) : assert(planCacheSize >= 0, 'a cache size is not negative');

  /// The directive definitions the schema declares besides the specified
  /// ones.
  final List<SchemaDirective> directives;

  /// Whether the schema has the `@defer` and `@stream` definitions.
  final bool includesDeferAndStream;

  /// The schema's description, null when it has none.
  final String? description;

  /// How many operation plans the schema keeps (least recently used first
  /// out); zero keeps none.
  final int planCacheSize;

  /// The global middleware, outermost first; each sees every resolver field
  /// and returns `next` for those it ignores.
  final List<FieldMiddleware<C>> middleware;

  /// Middleware by directive name, applied to the fields that carry the
  /// directive. A name the schema does not define is an [ArgumentError] when
  /// the schema is built.
  final Map<String, DirectiveMiddleware<C>> directiveMiddleware;

  /// Decides the access to the fields an `Authorization.requires` rule
  /// guards; a schema with such fields and no authorizer fails to build
  /// (`GQL304`).
  final Authorizer<C>? authorizer;
}
