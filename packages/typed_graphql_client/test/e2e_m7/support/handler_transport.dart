import 'dart:async';

import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// An [HttpTransport] that serves each request with M7's
/// [GraphQLHttpHandler], with no network, as a host adapter would.
///
/// The request body is streamed to the handler as the client wrote it; a
/// `FixedBody` comes back as one chunk and a `StreamedBody` as its stream.
/// The client's abort cancels the request's [CancelSignal], as a host does
/// when the client goes away.
final class HandlerTransport implements HttpTransport {
  /// Creates a transport over [handler].
  HandlerTransport(this.handler);

  /// The handler that answers.
  final GraphQLHttpHandler<Object?> handler;

  /// Every request method, in order.
  final List<String> methods = [];

  /// Every response status, in order.
  final List<int> statuses = [];

  /// Every response's `content-type` header, in order.
  final List<String?> contentTypes = [];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final signal = CancelSignal();
    unawaited(request.abortTrigger?.then((_) => signal.cancel()));
    final response = await handler.handle(
      HttpRequestData(
        method: request.method,
        uri: request.uri,
        headers: request.headers,
        body: request.body ?? const Stream<List<int>>.empty(),
        cancelSignal: signal,
      ),
    );
    methods.add(request.method);
    statuses.add(response.status);
    contentTypes.add(response.headers['content-type']);
    return TransportResponse(
      statusCode: response.status,
      headers: response.headers,
      body: switch (response.body) {
        FixedBody(:final bytes) => Stream.value(bytes),
        StreamedBody(:final chunks) => chunks,
      },
    );
  }
}
