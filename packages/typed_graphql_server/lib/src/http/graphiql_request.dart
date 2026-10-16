import 'package:meta/meta.dart';

import 'accept_negotiation.dart';
import 'http_request_data.dart';
import 'response_media_type.dart';

/// Decides whether a request is a browser opening the endpoint, which gets
/// the GraphiQL page instead of an answer (spec section 12).
@internal
final class GraphiQLRequest {
  /// Creates the decision.
  const GraphiQLRequest();

  static const AcceptNegotiation _negotiation = AcceptNegotiation([]);

  /// Whether [request] is a `GET` without a `query` whose `Accept` ranks
  /// `text/html` above both JSON types.
  ///
  /// A missing `Accept` or `*/*` ranks them equally, so it is a GraphQL
  /// request that will fail as one. A query string that is not valid UTF-8 is
  /// not a page request either: the handler refuses it.
  bool wants(HttpRequestData request) {
    if (request.method.toUpperCase() != 'GET') return false;
    if (_hasQuery(request.uri)) return false;
    final accept = request.header('accept');
    final html = _negotiation.qualityOfName('text', 'html', accept);
    if (html <= 0) return false;
    return html > _bestJson(accept);
  }

  bool _hasQuery(Uri uri) {
    try {
      return uri.queryParametersAll['query']?.any((v) => v.isNotEmpty) ?? false;
    } on FormatException {
      return true;
    }
  }

  double _bestJson(String? accept) {
    var best = 0.0;
    for (final type in const [
      ResponseMediaType.graphqlResponseJson,
      ResponseMediaType.json,
    ]) {
      final quality = _negotiation.qualityOfName(
        type.type,
        type.subtype,
        accept,
      );
      if (quality > best) best = quality;
    }
    return best;
  }
}
