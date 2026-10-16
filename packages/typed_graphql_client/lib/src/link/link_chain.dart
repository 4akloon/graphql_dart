import 'package:meta/meta.dart';

import 'link.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// Links run in order, built by [Link.from].
@internal
final class LinkChain extends Link {
  /// Creates the chain of [links], copied.
  LinkChain(List<Link> links) : _links = List.unmodifiable(links);

  final List<Link> _links;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) =>
      _from(0, request, forward);

  /// The answer of the links from [index] on; past the last, [forward].
  Stream<LinkResult> _from(int index, LinkRequest request, NextLink forward) {
    if (index == _links.length) {
      return forward(request);
    }
    return _links[index].request(
      request,
      (next) => _from(index + 1, next, forward),
    );
  }
}
