import 'dart:async';

import 'package:http/http.dart' as http;

import 'http_transport.dart';
import 'transport_request.dart';
import 'transport_response.dart';

/// An [HttpTransport] over any `http.Client` of `package:http`: `IOClient`,
/// the browser's `BrowserClient`, `cupertino_http`, `cronet_http` and the
/// others (R8.4).
///
/// It sends an `http.AbortableStreamedRequest`, so completing a request's
/// `abortTrigger` closes the connection on every client that supports
/// aborting. The caller owns [client] and closes it.
///
/// {@category http}
final class PackageHttpTransport(
  /// The client that sends the requests.
  final http.Client client,
) implements HttpTransport {
  /// Creates a transport over [client].
  this;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final outgoing =
        http.AbortableStreamedRequest(
            request.method,
            request.uri,
            abortTrigger: request.abortTrigger,
          )
          ..headers.addAll(request.headers)
          ..contentLength = request.contentLength;
    final sink = outgoing.sink;
    final body = request.body;
    unawaited(
      body == null
          ? sink.close()
          : sink.addStream(body).whenComplete(sink.close),
    );
    final response = await client.send(outgoing);
    return TransportResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.stream,
    );
  }
}
