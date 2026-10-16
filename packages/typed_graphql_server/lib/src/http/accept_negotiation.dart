import 'package:meta/meta.dart';

import 'media_range.dart';
import 'response_media_type.dart';

/// Chooses the response media type from an `Accept` header (RFC 9110 section
/// 12.5.1).
@internal
final class AcceptNegotiation {
  /// Creates the negotiation over the [offered] types, in the server's order
  /// of preference.
  const AcceptNegotiation(this.offered);

  /// The types the server can write, most preferred first.
  final List<ResponseMediaType> offered;

  /// The offered type [accept] likes best, or null when it allows none.
  ///
  /// A missing or blank header gives [ResponseMediaType.json], the
  /// legacy-safe choice, when it is offered. Each offered type takes the
  /// quality of the most specific range that matches it; the highest quality
  /// above 0 wins and a tie goes to the earlier offered type. The header is
  /// split on every comma, so a comma inside a quoted parameter splits
  /// wrongly; that range is then ignored as invalid.
  ResponseMediaType? choose(String? accept) {
    if (accept == null || accept.trim().isEmpty) {
      return offered.contains(ResponseMediaType.json)
          ? ResponseMediaType.json
          : null;
    }
    final ranges = [
      for (final element in accept.split(',')) ?MediaRange.parse(element),
    ];
    ResponseMediaType? best;
    var bestQuality = 0.0;
    for (final candidate in offered) {
      final quality = _qualityOf(candidate, ranges);
      if (quality > bestQuality) {
        best = candidate;
        bestQuality = quality;
      }
    }
    return best;
  }

  double _qualityOf(ResponseMediaType candidate, List<MediaRange> ranges) {
    var specificity = -1;
    var quality = 0.0;
    for (final range in ranges) {
      final match = range.specificityFor(candidate);
      if (match == null || match < specificity) continue;
      if (match > specificity) quality = 0;
      specificity = match;
      if (range.quality > quality) quality = range.quality;
    }
    return quality;
  }
}
