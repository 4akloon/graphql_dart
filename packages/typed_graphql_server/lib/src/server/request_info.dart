import 'header_names.dart';

/// What the transport knows about one request, besides the GraphQL
/// parameters: the context factory and the extensions read it (R5.1).
///
/// {@category server}
final class RequestInfo {
  /// Creates the information about a request.
  ///
  /// [headers] names are lower-cased. [source] is the host's own request
  /// object (for example a `shelf` request); the library never reads it.
  RequestInfo({
    required this.method,
    required this.uri,
    Map<String, String> headers = const {},
    this.source,
  }) : headers = const HeaderNames().lowerCased(headers);

  /// The HTTP method as the transport gave it; the pipeline compares it with
  /// `GET` ignoring case.
  final String method;

  /// The URI the request was sent to.
  final Uri uri;

  /// The headers, unmodifiable, with lower-case names. A transport joins
  /// repeated values with `, `.
  final Map<String, String> headers;

  /// The host's own request object, never read by the library.
  final Object? source;

  /// The value of the header [name], whatever its case, or null.
  String? header(String name) => headers[name.toLowerCase()];
}
