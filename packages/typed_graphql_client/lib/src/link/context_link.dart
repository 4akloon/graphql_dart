import 'dart:async';

import '../client/client_failure.dart';
import 'link.dart';
import 'link_context.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// Rewrites the context of each request before forwarding it, such as to
/// add headers computed at the time of the request (R8.4).
///
/// An [Exception] thrown by [update] is a [NetworkFailure] result and the
/// request is not forwarded.
///
/// {@category link}
final class ContextLink(
  /// The new context of a request, from the request.
  final FutureOr<LinkContext> Function(LinkRequest request) update,
) extends Link {
  /// Creates a link that rewrites contexts with [update].
  this;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) async* {
    final LinkContext context;
    try {
      context = await update(request);
    } on Exception catch (exception) {
      yield LinkFailure(NetworkFailure(exception));
      return;
    }
    yield* forward(request.withContext(context));
  }
}
