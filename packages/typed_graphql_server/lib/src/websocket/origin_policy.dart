import 'package:meta/meta.dart';

import '../server/request_info.dart';

/// Decides whether a WebSocket upgrade may proceed, from its `Origin`.
///
/// A browser sends cookies with an upgrade and no preflight, so a page on
/// another site could open an authenticated socket; checking the origin is
/// the defence against that cross-site hijacking (spec section 9).
@internal
final class OriginPolicy {
  /// Creates a policy that also allows the exact origins in [allowedOrigins].
  const OriginPolicy(this.allowedOrigins);

  /// The origins allowed besides the host's own, compared ignoring case.
  final List<String>? allowedOrigins;

  /// Whether [upgrade] has no `Origin`, the host's own or a listed one.
  bool allows(RequestInfo upgrade) {
    final origin = upgrade.header('origin');
    if (origin == null) {
      return true;
    }
    // A sandboxed frame or a redirect sends the literal `null`; it names no
    // site, so no host comparison can vouch for it.
    if (origin.toLowerCase() == 'null') {
      return false;
    }
    return _isListed(origin) || _isSameHost(origin, upgrade.header('host'));
  }

  bool _isListed(String origin) {
    final lowered = origin.toLowerCase();
    return allowedOrigins?.any((listed) => listed.toLowerCase() == lowered) ??
        false;
  }

  bool _isSameHost(String origin, String? host) {
    final uri = Uri.tryParse(origin);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty || host == null) {
      return false;
    }
    // `Uri` drops the default port of the scheme from the authority.
    return uri.authority.toLowerCase() == host.toLowerCase();
  }
}
