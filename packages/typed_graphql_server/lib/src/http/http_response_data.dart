import '../server/header_names.dart';
import 'http_response_body.dart';

/// What `GraphQLHttpHandler` answers: a status, headers and a body, for the
/// host to write (R5.5).
///
/// {@category http}
final class HttpResponseData {
  /// Creates a response with [status]; [headers] names are lower-cased.
  HttpResponseData(
    this.status, {
    Map<String, String> headers = const {},
    this.body = const FixedBody([]),
  }) : headers = const HeaderNames().lowerCased(headers);

  /// The HTTP status code.
  final int status;

  /// The headers, unmodifiable, with lower-case names.
  final Map<String, String> headers;

  /// The body.
  final HttpResponseBody body;
}
