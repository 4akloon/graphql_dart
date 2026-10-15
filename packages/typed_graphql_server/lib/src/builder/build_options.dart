import 'package:typed_graphql/typed_graphql.dart';

/// The settings of `ExecutableSchemaBuilder.build` besides the root types.
///
/// Grouped in one object to keep `build` within five parameters; later
/// stages add their settings here (plan cache size, middleware).
///
/// {@category builder}
final class BuildOptions {
  /// Creates the options.
  const BuildOptions({
    this.directives = const [],
    this.includesDeferAndStream = false,
    this.description,
    this.planCacheSize = 1000,
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
}
