import 'link_chain.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// One step between the client and the server (R8.3): it may change a
/// request, answer it, or forward it and change the answer.
///
/// A middle link calls `forward`; a terminating link (`MockLink`, and
/// `HttpLink` from M11b) ignores it and talks to a server. [request] returns a
/// stream: one event for a query or a mutation, many for a subscription.
/// Failures are [LinkFailure] events, never stream errors. Cancelling the
/// subscription to the stream ends the request in every link: a link that
/// holds a resource releases it in the stream's `onCancel`.
///
/// {@category link}
abstract base class Link {
  /// Creates a link.
  const Link();

  /// The answer to [request]; [forward] sends a request to the rest of the
  /// chain.
  Stream<LinkResult> request(LinkRequest request, NextLink forward);

  /// One link that runs [links] in order: each one's `forward` calls the
  /// next, and the last one's calls the `forward` of the chain. An empty
  /// list is an [ArgumentError].
  static Link from(List<Link> links) => switch (links) {
    [] => throw ArgumentError.value(links, 'links', 'is empty'),
    [final link] => link,
    _ => LinkChain(links),
  };
}
