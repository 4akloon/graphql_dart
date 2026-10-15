/// Where the generator finds the schema (R7.1): a file in the project or an
/// introspection URL.
///
/// {@category codegen}
sealed class const SchemaLocation() {
  /// Creates a location.
  this;
}

/// A schema file: SDL, or an introspection result when the path ends with
/// `.json`.
///
/// {@category codegen}
final class const SchemaFile(
  /// The path from the configuration file's folder, with `/` separators.
  final String path,
) extends SchemaLocation {
  /// Creates the location of the file at [path].
  this;

  /// Whether the file holds an introspection result rather than SDL.
  bool get isIntrospection => path.endsWith('.json');

  @override
  bool operator ==(Object other) => other is SchemaFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// A GraphQL endpoint the CLI asks for its schema with the introspection
/// query.
///
/// {@category codegen}
final class SchemaUrl(
  /// The endpoint, `http` or `https`.
  final Uri url,
) extends SchemaLocation {
  /// Creates the location of the endpoint at [url].
  this;

  @override
  bool operator ==(Object other) => other is SchemaUrl && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
