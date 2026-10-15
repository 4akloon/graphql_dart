import 'package:typed_graphql/typed_graphql.dart';

/// An error that a resolver, a scalar or an input object's `decode` throws
/// on purpose and that reaches the client as it is: [message] and
/// [extensions] go into the response without masking.
///
/// {@category execution}
final class GraphQLException implements Exception {
  /// Creates an exception with [message] and optional [extensions].
  const GraphQLException(this.message, {this.extensions});

  /// What the client reads.
  final String message;

  /// The `extensions` of the response error; null for none.
  final JsonObject? extensions;

  @override
  String toString() => message;
}
