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

  /// The offered types worded for a message: `a, b and c`.
  String get description {
    final names = [for (final type in offered) type.mediaType];
    return names.length < 2
        ? names.join()
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

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
    final ranges = _rangesOf(accept);
    ResponseMediaType? best;
    var bestQuality = 0.0;
    for (final candidate in offered) {
      final quality = _qualityOf(candidate.type, candidate.subtype, ranges);
      if (quality > bestQuality) {
        best = candidate;
        bestQuality = quality;
      }
    }
    return best;
  }

  /// The quality [accept] gives to `type/subtype`, or 0 when it is missing,
  /// blank or excludes it.
  ///
  /// Unlike [choose], a missing header gives nothing: the caller decides what
  /// a client that did not say means.
  double qualityOfName(String type, String subtype, String? accept) =>
      accept == null ? 0 : _qualityOf(type, subtype, _rangesOf(accept));

  static List<MediaRange> _rangesOf(String accept) => [
    for (final element in accept.split(',')) ?MediaRange.parse(element),
  ];

  double _qualityOf(String type, String subtype, List<MediaRange> ranges) {
    var specificity = -1;
    var quality = 0.0;
    for (final range in ranges) {
      final match = range.specificityForName(type, subtype);
      if (match == null || match < specificity) continue;
      if (match > specificity) quality = 0;
      specificity = match;
      if (range.quality > quality) quality = range.quality;
    }
    return quality;
  }
}
