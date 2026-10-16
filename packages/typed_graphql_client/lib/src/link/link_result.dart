import 'package:typed_graphql/typed_graphql.dart';

import '../client/client_failure.dart';
import 'link_context.dart';

/// One event of a link's answer: a GraphQL response, or why there is none.
///
/// Links report failures as [LinkFailure] values, never as stream errors.
///
/// {@category link}
sealed class LinkResult {
  /// Creates a result.
  const LinkResult();
}

/// A GraphQL response, untyped, with what the terminating link learned
/// about it in [context].
///
/// {@category link}
final class const LinkPayload(
  /// The response as the server sent it.
  final ResponsePayload payload, {

  /// Information about the answer, such as `HttpResponseInfo`.
  final LinkContext context = const LinkContext.empty(),
}) extends LinkResult {
  /// Creates a payload result.
  this;

  @override
  String toString() => 'LinkPayload($payload)';
}

/// A request that got no GraphQL response, and why.
///
/// {@category link}
final class const LinkFailure(
  /// Why there is no response.
  final ClientFailure failure,
) extends LinkResult {
  /// Creates a failure result.
  this;

  @override
  String toString() => 'LinkFailure($failure)';
}
