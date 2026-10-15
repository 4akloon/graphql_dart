import 'package:typed_graphql/typed_graphql.dart';

import '../execution/schema_bindings.dart';

/// What every step of input coercion reads and none changes: the core schema
/// for the types, the bindings for the Dart side (codecs, enums, `decode`),
/// and whether messages carry "Did you mean" text.
final class CoercionEnvironment(
  /// The core schema.
  final Schema schema,

  /// The Dart definitions behind the schema.
  final SchemaBindings bindings, {

  /// Whether messages suggest names, as graphql-js's do unless
  /// `hideSuggestions` is set.
  final bool includesSuggestions = true,
}) {
  /// Creates the environment.
  this;
}
