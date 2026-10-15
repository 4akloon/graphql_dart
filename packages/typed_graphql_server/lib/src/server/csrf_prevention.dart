import 'request_info.dart';

/// The cross-site request forgery rule of a server (R5.4, R5.15): a request
/// passes with a content type a browser cannot send cross-site without a
/// preflight, or with a non-empty custom header.
///
/// {@category server}
final class CsrfPrevention {
  /// Creates the rule; [requestHeaders] replace [defaultHeaders].
  const CsrfPrevention({this.requestHeaders = defaultHeaders});

  /// The headers Apollo Server and GraphQL Yoga accept, so Apollo clients
  /// pass.
  static const List<String> defaultHeaders = [
    'graphql-require-preflight',
    'apollo-require-preflight',
    'x-apollo-operation-name',
  ];

  /// The message of the `GQL403` error, for the default headers.
  static const String message =
      'This operation has been blocked as a potential Cross-Site Request '
      "Forgery (CSRF). Please either specify a 'content-type' header (with a "
      'type that is not one of application/x-www-form-urlencoded, '
      'multipart/form-data, text/plain) or provide a non-empty value for one '
      'of the following headers: ';

  static const List<String> _simpleTypes = [
    'application/x-www-form-urlencoded',
    'multipart/form-data',
    'text/plain',
  ];

  // RFC 7230 token: type "/" subtype.
  static final RegExp _mediaType = RegExp(
    r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+/[!#$%&'*+.^_`|~0-9A-Za-z-]+$",
  );

  /// The header names, any of which with a non-empty value lets a request
  /// pass.
  final List<String> requestHeaders;

  /// The refusal text for this rule, naming [requestHeaders].
  String get refusal => '$message${requestHeaders.join(', ')}.';

  /// Whether the request in [info] passes (September 2025 is silent; this is
  /// Apollo Server's rule).
  bool allows(RequestInfo info) =>
      _hasPreflightingType(info.header('content-type')) ||
      requestHeaders.any(
        (name) => (info.header(name) ?? '').trim().isNotEmpty,
      );

  bool _hasPreflightingType(String? contentType) {
    if (contentType == null) return false;
    final mediaType = contentType.split(';').first.trim().toLowerCase();
    return _mediaType.hasMatch(mediaType) && !_simpleTypes.contains(mediaType);
  }

  @override
  bool operator ==(Object other) =>
      other is CsrfPrevention &&
      other.requestHeaders.length == requestHeaders.length &&
      [for (final name in other.requestHeaders) name.toLowerCase()].join(
            '\n',
          ) ==
          [for (final name in requestHeaders) name.toLowerCase()].join('\n');

  @override
  int get hashCode =>
      Object.hashAll([for (final name in requestHeaders) name.toLowerCase()]);
}
