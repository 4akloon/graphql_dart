/// One HTTP request as the HTTP links hand it to an `HttpTransport`.
///
/// {@category http}
final class TransportRequest({
  /// The HTTP method, `GET` or `POST`.
  required final String method,

  /// The URL, with the query parameters of a `GET` request.
  required final Uri uri,
  Map<String, String> headers = const {},

  /// The body, read once; null for a request without one.
  final Stream<List<int>>? body,

  /// The body's length in bytes, when it is known before sending.
  final int? contentLength,

  /// Completes when the link no longer wants the answer: the transport
  /// should then close the connection.
  final Future<void>? abortTrigger,
}) {
  /// Creates a request; [headers] is copied with its names in lower case.
  this;

  /// The headers, names in lower case.
  final Map<String, String> headers = Map.unmodifiable({
    for (final MapEntry(:key, :value) in headers.entries)
      key.toLowerCase(): value,
  });

  @override
  String toString() => 'TransportRequest($method $uri)';
}
