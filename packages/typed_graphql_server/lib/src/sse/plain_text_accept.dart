import 'package:meta/meta.dart';

import '../http/accept_negotiation.dart';

/// Decides whether an `Accept` header allows `text/plain`, the type of a
/// reservation token (spec section 10).
@internal
final class PlainTextAccept {
  /// Creates the check.
  const PlainTextAccept();

  /// The `content-type` of the token.
  static const String contentType = 'text/plain; charset=utf-8';

  /// Whether [accept] allows `text/plain`: it is missing or blank, or the most
  /// specific range that matches it (`text/plain`, `text/*`, `*/*`) has a
  /// quality above 0.
  bool allows(String? accept) {
    if (accept == null || accept.trim().isEmpty) return true;
    return const AcceptNegotiation([]).qualityOfName('text', 'plain', accept) >
        0;
  }
}
