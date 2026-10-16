import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

import '../client/client_failure.dart';
import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import 'http_exchange.dart';
import 'http_request_encoder.dart';
import 'http_transport.dart';
import 'response_reader.dart';

/// A terminating link that sends queries and mutations over GraphQL over
/// HTTP through an [HttpTransport] (spec section 9, R8.4).
///
/// A request is a `POST` with a JSON body, or with [usesGetForQueries] a
/// query is a `GET` with query parameters; every request asks for
/// `application/graphql-response+json`. The answer is read by the GraphQL
/// over HTTP rules: a GraphQL response whatever the status, plain JSON only
/// with a 2xx status, at most [maxResponseBytes] bytes and
/// [maxResponseDepth] levels of nesting. The payload's context holds an
/// `HttpResponseInfo` with the status and headers. Cancelling the result
/// stream aborts the request. A request with `UploadFiles` in its context
/// is a multipart `POST`. A subscription is refused: route it to a
/// streaming link with a `SplitLink`.
///
/// {@category http}
final class HttpLink extends Link {
  /// Creates a link that sends to [uri] through [transport], adding
  /// [headers] to every request and giving up after [timeout]; with
  /// [usesGetForQueries], queries go as `GET` requests; [random] draws the
  /// boundaries of multipart bodies.
  HttpLink({
    required Uri uri,
    required HttpTransport transport,
    Map<String, String> headers = const {},
    bool usesGetForQueries = false,
    Duration? timeout,
    int maxResponseBytes = defaultMaxResponseBytes,
    int maxResponseDepth = JsonReader.defaultMaxDepth,
    Random? random,
  }) : _encoder = HttpRequestEncoder(
         uri: uri,
         headers: headers,
         usesGetForQueries: usesGetForQueries,
         random: random ?? Random(),
       ),
       _exchange = HttpExchange(
         transport: transport,
         reader: ResponseReader(
           maxBytes: maxResponseBytes,
           maxDepth: maxResponseDepth,
         ),
         timeout: timeout,
       ) {
    RangeError.checkNotNegative(maxResponseBytes, 'maxResponseBytes');
    RangeError.checkValueInInterval(
      maxResponseDepth,
      1,
      JsonReader.maxSupportedDepth,
      'maxResponseDepth',
    );
  }

  /// The default of `maxResponseBytes`: 16 MiB.
  static const int defaultMaxResponseBytes = 16 * 1024 * 1024;

  final HttpRequestEncoder _encoder;
  final HttpExchange _exchange;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    if (request.type == .subscription) {
      return Stream.value(
        LinkFailure(
          UnsupportedOperation(
            .operationNotSupportedByLink,
            'HttpLink cannot carry the subscription '
            '${request.document.name}; send subscriptions over WebSocketLink '
            'or SseLink with a SplitLink.',
          ),
        ),
      );
    }
    return _exchange.run(
      (abortTrigger) => _encoder.encode(request, abortTrigger),
    );
  }
}
