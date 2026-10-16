import 'package:meta/meta.dart';

import '../http/media_range.dart';

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
    var specificity = -1;
    var quality = 0.0;
    for (final element in accept.split(',')) {
      final range = MediaRange.parse(element);
      final match = range == null ? null : _specificity(range);
      if (range == null || match == null || match < specificity) continue;
      if (match > specificity) quality = 0;
      specificity = match;
      if (range.quality > quality) quality = range.quality;
    }
    return quality > 0;
  }

  // 2 for the exact type, 1 for `text/*`, 0 for `*/*`, null for no match.
  int? _specificity(MediaRange range) {
    if (range.type == '*') return 0;
    if (range.type != 'text') return null;
    if (range.subtype == '*') return 1;
    return range.subtype == 'plain' ? 2 : null;
  }
}
