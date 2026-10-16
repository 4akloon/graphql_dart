import 'package:meta/meta.dart';

import 'response_media_type.dart';

/// One element of an `Accept` header: a media range and its quality (RFC 9110
/// section 12.5.1).
@internal
final class MediaRange {
  /// Creates a range of [type] and [subtype], either of which may be `*`.
  const MediaRange(this.type, this.subtype, this.quality);

  /// The top-level type, lower-case, or `*`.
  final String type;

  /// The subtype, lower-case, or `*`.
  final String subtype;

  /// The weight of the range, from 0 (excluded) to 1.
  final double quality;

  // The grammar of a `qvalue`: at most three decimals, nothing above 1.
  static final RegExp _quality = RegExp(
    r'^(?:0(?:\.\d{0,3})?|1(?:\.0{0,3})?)$',
  );

  /// The range of one comma-separated [element], or null when it is invalid
  /// (a missing slash, an empty part, a `q` that is not a number from 0 to 1
  /// with at most three decimals), so the caller ignores it.
  ///
  /// Parameters other than `q` are ignored.
  static MediaRange? parse(String element) {
    final parts = element.split(';');
    final name = parts.first.trim().toLowerCase().split('/');
    if (name.length != 2) return null;
    final [type, subtype] = name;
    if (!_isToken(type) || !_isToken(subtype)) return null;
    if (type == '*' && subtype != '*') return null;
    final quality = _qualityOf(parts.skip(1));
    return quality == null ? null : MediaRange(type, subtype, quality);
  }

  /// How closely this range names [offered]: 2 for the exact type, 1 for
  /// `type/*`, 0 for `*/*`, null when it does not match.
  int? specificityFor(ResponseMediaType offered) =>
      specificityForName(offered.type, offered.subtype);

  /// [specificityFor] for a media type that is not a [ResponseMediaType], such
  /// as the GraphiQL page's `text/html`.
  int? specificityForName(String offeredType, String offeredSubtype) {
    if (type == '*') return 0;
    if (type != offeredType) return null;
    if (subtype == '*') return 1;
    return subtype == offeredSubtype ? 2 : null;
  }

  static bool _isToken(String text) =>
      text.isNotEmpty && !text.contains(_whitespace);

  static final RegExp _whitespace = RegExp(r'\s');

  // The weight given by the first `q` parameter, 1 without one, null when it
  // is malformed.
  static double? _qualityOf(Iterable<String> parameters) {
    for (final parameter in parameters) {
      final pair = parameter.split('=');
      if (pair.first.trim().toLowerCase() != 'q') continue;
      final value = pair.length == 2 ? pair[1].trim() : '';
      return _quality.hasMatch(value) ? double.tryParse(value) : null;
    }
    return 1;
  }
}
