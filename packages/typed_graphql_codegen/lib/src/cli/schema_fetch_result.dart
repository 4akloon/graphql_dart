import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';

/// What [SchemaFetcher] got from a schema URL.
///
/// {@category codegen}
sealed class SchemaFetchResult {
  const SchemaFetchResult();
}

/// The server answered with a 2xx status.
///
/// {@category codegen}
final class SchemaFetched(
  /// The response body, at the path `'<url>.json'` so that the engine reads
  /// it as an introspection result.
  final ProjectFile file,
) extends SchemaFetchResult {
  /// Creates the result.
  this;
}

/// The schema could not be fetched.
///
/// {@category codegen}
final class SchemaFetchFailed(
  /// The `GQL510` that says why; it never holds a header value.
  final Diagnostic diagnostic,
) extends SchemaFetchResult {
  /// Creates the result.
  this;
}
