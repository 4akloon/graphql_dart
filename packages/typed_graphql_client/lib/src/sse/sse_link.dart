import 'dart:convert';
import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

import '../client/client_failure.dart';
import '../http/http_request_encoder.dart';
import '../http/http_transport.dart';
import '../http/response_reader.dart';
import '../http/transport_request.dart';
import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import '../upload/upload_files.dart';
import 'event_stream_parser.dart';
import 'sse_exchange.dart';

/// A terminating link that sends queries, mutations and subscriptions over
/// server-sent events, in graphql-sse's distinct connections mode (spec
/// section 9, R8.4).
///
/// Each operation is a `POST` with a JSON body that asks for
/// `text/event-stream`; the answer is an event stream whose `next` events
/// are the results, delivered as they arrive, and whose `complete` event
/// ends the stream. An answer that is not an event stream is read as
/// [HttpLink] reads it, so a request the server refuses with a GraphQL
/// response is an errors response. An event is bounded by `maxEventBytes`.
/// Cancelling the result stream closes the connection, which is how the
/// protocol stops an operation. There is no timeout: a subscription lives
/// as long as the caller listens. Single connection mode is not supported.
/// A request with `UploadFiles` in its context is refused with
/// `UnsupportedOperation` (`GQL468`) without sending anything.
///
/// {@category sse}
final class SseLink extends Link {
  /// Creates a link that sends to [uri] through [transport], adding
  /// [headers] to every request; no event may pass [maxEventBytes], and the
  /// JSON of an event may nest [maxResponseDepth] levels.
  SseLink({
    required Uri uri,
    required HttpTransport transport,
    Map<String, String> headers = const {},
    int maxEventBytes = defaultMaxEventBytes,
    int maxResponseDepth = JsonReader.defaultMaxDepth,
  }) : _uri = uri,
       _encoder = HttpRequestEncoder(
         uri: uri,
         headers: headers,
         usesGetForQueries: false,
         random: Random(),
       ),
       _exchange = SseExchange(
         transport: transport,
         reader: ResponseReader(
           maxBytes: maxEventBytes,
           maxDepth: maxResponseDepth,
         ),
         parser: EventStreamParser(maxEventBytes: maxEventBytes),
       ) {
    RangeError.checkNotNegative(maxEventBytes, 'maxEventBytes');
    RangeError.checkValueInInterval(
      maxResponseDepth,
      1,
      JsonReader.maxSupportedDepth,
      'maxResponseDepth',
    );
  }

  /// The default of `maxEventBytes`: 16 MiB.
  static const int defaultMaxEventBytes = 16 * 1024 * 1024;

  static const Map<String, String> _protocolHeaders = {
    'accept': 'text/event-stream',
    'content-type': 'application/json',
  };

  final Uri _uri;
  final HttpRequestEncoder _encoder;
  final SseExchange _exchange;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    if (request.context.entry<UploadFiles>() != null) {
      return Stream.value(
        LinkFailure(
          UnsupportedOperation(
            .operationNotSupportedByLink,
            'SseLink cannot send files with ${request.document.name}; send '
            'it over HttpLink with a SplitLink.',
          ),
        ),
      );
    }
    return _exchange.run((abortTrigger) {
      final body = utf8.encode(jsonEncode(request.body.toJson().toJson()));
      return TransportRequest(
        method: 'POST',
        uri: _uri,
        headers: _encoder.headersFor(request, _protocolHeaders),
        body: Stream.value(body),
        contentLength: body.length,
        abortTrigger: abortTrigger,
      );
    });
  }
}
