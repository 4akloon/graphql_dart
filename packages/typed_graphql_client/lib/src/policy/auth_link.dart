import 'dart:async';

import '../client/client_failure.dart';
import '../link/http_response_info.dart';
import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import '../link/request_headers.dart';
import 'auth_run.dart';
import 'token_renewal.dart';

/// Adds an authentication token to each request and renews it when the server
/// refuses it (R8.4).
///
/// Before forwarding, the link calls [token] and, when it gives a string,
/// adds the header `<headerName>: <scheme> <token>` to the request's
/// `RequestHeaders` (just the token when [scheme] is empty); a null token adds
/// nothing. When the answer is a 401 (the default [isUnauthorized]: an
/// `HttpStatusFailure` with status 401, or a payload whose `HttpResponseInfo`
/// has it) and a [refresh] callback was given, the link asks [token] again: a
/// new token, such as one a concurrent request stored, is sent as it is;
/// otherwise [refresh] runs, once for every request that waits for it at the
/// same time, and the request is sent again with its result. A request is
/// sent again at most once; a refresh that is missing or gives null leaves the
/// 401 as the answer. An [Exception] thrown by [token] or [refresh] is a
/// `LinkFailure` holding an `AuthenticationFailure`, and the request is not
/// forwarded again; an error that is not an [Exception], and anything thrown
/// by [isUnauthorized], ends the stream as an error. A stream error from the
/// links below reaches the caller untouched.
///
/// {@category policy}
final class AuthLink extends Link {
  /// Creates a link that reads the token with [token]; [refresh] renews it.
  AuthLink({
    required this.token,
    this.refresh,
    this.headerName = 'authorization',
    this.scheme = 'Bearer',
    bool Function(LinkResult result)? isUnauthorized,
  }) : isUnauthorized = isUnauthorized ?? _isHttpUnauthorized,
       _renewal = TokenRenewal(token, refresh);

  /// Gives the token to send, or null to send none.
  final FutureOr<String?> Function() token;

  /// Fetches a new token after a 401, or null when the token cannot be
  /// renewed.
  final Future<String?> Function()? refresh;

  /// The header that carries the token.
  final String headerName;

  /// The word before the token in the header; empty for none.
  final String scheme;

  /// Whether a result says the server refused the token.
  final bool Function(LinkResult result) isUnauthorized;

  final TokenRenewal _renewal;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) => AuthRun(
    request,
    forward,
    renewal: _renewal,
    authorize: _authorize,
    isUnauthorized: isUnauthorized,
  ).results;

  LinkRequest _authorize(LinkRequest request, String? token) {
    if (token == null) {
      return request;
    }
    final value = scheme.isEmpty ? token : '$scheme $token';
    final headers = request.context.entry<RequestHeaders>();
    return request.withContext(
      request.context.withEntry(
        (headers ?? RequestHeaders(const {})).withHeader(headerName, value),
      ),
    );
  }

  static bool _isHttpUnauthorized(LinkResult result) => switch (result) {
    LinkFailure(failure: HttpStatusFailure(statusCode: 401)) => true,
    LinkPayload(:final context) =>
      context.entry<HttpResponseInfo>()?.statusCode == 401,
    _ => false,
  };
}
