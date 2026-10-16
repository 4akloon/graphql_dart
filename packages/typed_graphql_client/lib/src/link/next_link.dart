import 'link_request.dart';
import 'link_result.dart';

/// The rest of a link chain, as a link sees it: call it with the request
/// to forward, and get the answer's stream.
///
/// {@category link}
typedef NextLink = Stream<LinkResult> Function(LinkRequest request);
