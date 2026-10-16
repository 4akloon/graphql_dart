import 'package:meta/meta.dart';

import '../http/http_transport.dart';
import '../http/response_reader.dart';
import '../http/transport_request.dart';
import '../link/link_result.dart';
import 'event_stream_parser.dart';
import 'sse_run.dart';

/// Runs the requests of `SseLink`: each starts when its stream is listened
/// to and ends, with the connection, when the stream is cancelled or the
/// server completes it (graphql-sse, distinct connections mode).
@internal
final class SseExchange({
  /// Sends the requests.
  required final HttpTransport transport,

  /// Reads the answers that are not event streams, and each `next` event.
  required final ResponseReader reader,

  /// Reads the event streams.
  required final EventStreamParser parser,
}) {
  /// Creates an exchange.
  this;

  /// The results of the request [encode] writes; [encode] gets the
  /// request's abort trigger.
  Stream<LinkResult> run(
    TransportRequest Function(Future<void> abortTrigger) encode,
  ) =>
      SseRun(transport: transport, reader: reader, parser: parser).open(encode);
}
