import 'package:meta/meta.dart';

/// The parts of a `Content-Type` header the HTTP links decide on: the
/// media type before `;` and its `charset` parameter, both in lower case.
@internal
final class MediaType {
  /// Reads [header]; a missing header has no [essence].
  factory MediaType.parse(String? header) {
    if (header == null || header.trim().isEmpty) {
      return const MediaType._(null, null);
    }
    final parts = header.split(';');
    String? charset;
    for (final parameter in parts.skip(1)) {
      final separator = parameter.indexOf('=');
      if (separator < 0) continue;
      if (parameter.substring(0, separator).trim().toLowerCase() == 'charset') {
        charset = _unquoted(parameter.substring(separator + 1).trim());
      }
    }
    return MediaType._(parts.first.trim().toLowerCase(), charset);
  }

  const MediaType._(this.essence, this.charset);

  /// The media type of a GraphQL response, GraphQL over HTTP's own.
  static const String graphQLResponse = 'application/graphql-response+json';

  /// The legacy media type of a GraphQL response.
  static const String json = 'application/json';

  /// The media type of a server-sent event stream.
  static const String eventStream = 'text/event-stream';

  /// The type and subtype, such as `application/json`; null when the
  /// header is missing.
  final String? essence;

  /// The `charset` parameter, lower-cased and unquoted; null when absent.
  final String? charset;

  /// Whether the body is UTF-8: no charset, or `utf-8`.
  bool get isUtf8 => charset == null || charset == 'utf-8';

  static String _unquoted(String value) {
    final text =
        value.length >= 2 && value.startsWith('"') && value.endsWith('"')
        ? value.substring(1, value.length - 1)
        : value;
    return text.toLowerCase();
  }

  @override
  String toString() => essence ?? '(none)';
}
