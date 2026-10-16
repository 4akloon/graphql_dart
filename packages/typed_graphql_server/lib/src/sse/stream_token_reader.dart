import 'package:meta/meta.dart';

import '../http/http_request_data.dart';

/// Reads what a request of single connection mode carries: the stream token
/// and the `operationId` parameter of a `DELETE`.
@internal
final class StreamTokenReader {
  /// Creates the reader.
  const StreamTokenReader();

  /// The header that carries the token.
  static const String header = 'x-graphql-event-stream-token';

  /// The token of [request]: the header, else the `token` parameter. Null when
  /// there is none or it is empty.
  String? tokenOf(HttpRequestData request) {
    final fromHeader = request.header(header);
    if (fromHeader != null && fromHeader.isNotEmpty) return fromHeader;
    return _parameter(request, 'token');
  }

  /// The `operationId` parameter of [request], or null.
  String? operationIdOf(HttpRequestData request) =>
      _parameter(request, 'operationId');

  // A query string with a bad escape throws when it is decoded; to the
  // reader it is no parameter.
  String? _parameter(HttpRequestData request, String name) {
    try {
      final value = request.uri.queryParameters[name];
      return value == null || value.isEmpty ? null : value;
    } on FormatException {
      return null;
    }
  }
}
