import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// Turns the [HttpResponseData] of the HTTP handler into a shelf [Response].
@internal
final class ResponseConversion {
  /// Creates the conversion.
  const ResponseConversion();

  /// The response for [data].
  ///
  /// A streamed body asks `shelf_io` not to buffer its output, so each chunk
  /// (an event of a stream) reaches the client when it is written.
  Response convert(HttpResponseData data) => switch (data.body) {
    FixedBody(:final bytes) => Response(
      data.status,
      body: bytes,
      headers: data.headers,
    ),
    StreamedBody(:final chunks) => Response(
      data.status,
      body: chunks,
      headers: data.headers,
      context: const {'shelf.io.buffer_output': false},
    ),
  };
}
