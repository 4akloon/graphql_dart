import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_context.dart';
import 'client_failure.dart';

/// The typed answer to an operation (R8.2): data, errors without data, or
/// a failure to get a response at all.
///
/// Switch over it; the three kinds tell apart what a caller handles
/// differently.
///
/// {@category client}
sealed class GraphQLResponse<D extends Object> {
  /// Creates a response.
  const GraphQLResponse();
}

/// The operation ran and gave [data]; [errors] is not empty when part of
/// it failed (partial data).
///
/// {@category client}
final class GraphQLData<D extends Object>(
  /// The data, read into the operation's generated classes.
  final D data, {
  List<GraphQLError> errors = const [],

  /// The response's `extensions`, null when it has none.
  final JsonObject? extensions,

  /// What the terminating link learned about the answer, such as
  /// `HttpResponseInfo`.
  final LinkContext context = const LinkContext.empty(),
}) extends GraphQLResponse<D> {
  /// Creates a data response; [errors] is copied.
  this;

  /// The errors raised on the way, in order.
  final List<GraphQLError> errors = List.unmodifiable(errors);

  /// Whether part of the data failed.
  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() => 'GraphQLData($data, errors: $errors)';
}

/// The server answered with errors and no data: the request was refused
/// (a syntax or validation error, a persisted query miss) or an error
/// nulled the whole result.
///
/// {@category client}
final class GraphQLErrors<D extends Object>(
  List<GraphQLError> errors, {

  /// The response's `extensions`, null when it has none.
  final JsonObject? extensions,

  /// What the terminating link learned about the answer, such as
  /// `HttpResponseInfo`.
  final LinkContext context = const LinkContext.empty(),
}) extends GraphQLResponse<D> {
  /// Creates an error response; [errors] is copied.
  this;

  /// The errors, in order; never empty.
  final List<GraphQLError> errors = List.unmodifiable(errors);

  @override
  String toString() => 'GraphQLErrors($errors)';
}

/// No GraphQL response: [failure] says why.
///
/// {@category client}
final class const GraphQLTransportFailure<D extends Object>(
  /// Why there is no response.
  final ClientFailure failure,
) extends GraphQLResponse<D> {
  /// Creates a failure response.
  this;

  @override
  String toString() => 'GraphQLTransportFailure($failure)';
}
