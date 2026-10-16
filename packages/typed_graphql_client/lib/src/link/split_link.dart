import 'link.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// Sends a request down one of two links, chosen by [test]: typically
/// subscriptions over a socket and the rest over HTTP (R8.3).
///
/// The chosen link gets the chain's `forward`, so a branch may be a middle
/// link or a whole chain.
///
/// {@category link}
final class SplitLink({
  /// Whether a request goes to [whenTrue].
  required final bool Function(LinkRequest request) test,

  /// The link for requests that pass [test].
  required final Link whenTrue,

  /// The link for the other requests.
  required final Link whenFalse,
}) extends Link {
  /// Creates a split between [whenTrue] and [whenFalse].
  this;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) =>
      (test(request) ? whenTrue : whenFalse).request(request, forward);
}
