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
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    // `asyncExpand` does not call `forward` once the listener cancelled
    // while the update was pending.
    return _updated(request).asyncExpand(
      (outcome) => switch (outcome) {
        (:final context?, failure: _) => forward(request.withContext(context)),
        (context: _, :final failure?) => Stream.value(LinkFailure(failure)),
        _ => const Stream<LinkResult>.empty(),
      },
    );
  }

  Stream<({LinkContext? context, ClientFailure? failure})> _updated(
    LinkRequest request,
  ) async* {
    try {
      yield (context: await update(request), failure: null);
    } on Exception catch (exception) {
      yield (context: null, failure: NetworkFailure(exception));
    }
  }
}
