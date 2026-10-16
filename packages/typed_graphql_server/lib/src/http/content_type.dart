import 'package:meta/meta.dart';

/// The parsed `content-type` header of a request: a media type and its
/// parameters.
@internal
final class ContentType {
  /// Creates a content type of [mediaType] (`type/subtype`, lower-case) with
  /// [parameters], whose names are lower-case and values unquoted.
  const ContentType(this.mediaType, this.parameters);

  /// `type/subtype`, lower-case.
  final String mediaType;

  /// The parameters by lower-case name; a repeated name keeps its last value.
  final Map<String, String> parameters;

  /// The lower-cased `charset` parameter, or null.
  String? get charset => parameters['charset']?.toLowerCase();

  static final RegExp _whitespace = RegExp(r'\s');

  /// The content type in [header], or null when it is missing or malformed
  /// (no `type/subtype`, a parameter without a value, an unterminated quote).
  static ContentType? parse(String? header) {
    if (header == null) return null;
    final segments = _split(header);
    if (segments == null) return null;
    final name = segments.first.trim().toLowerCase();
    final halves = name.split('/');
    if (halves.length != 2 || halves.any((half) => half.isEmpty)) return null;
    if (name.contains(_whitespace)) return null;
    final parameters = <String, String>{};
    for (final segment in segments.skip(1)) {
      if (segment.trim().isEmpty) continue;
      final parameter = _parameter(segment);
      if (parameter == null) return null;
      parameters[parameter.$1] = parameter.$2;
    }
    return ContentType(name, Map.unmodifiable(parameters));
  }

  // Splits at the `;` outside quotes; null for an unterminated quote.
  static List<String>? _split(String header) {
    final segments = <String>[];
    final current = StringBuffer();
    var isQuoted = false;
    var isEscaped = false;
    for (final unit in header.split('')) {
      if (isEscaped) {
        isEscaped = false;
      } else if (isQuoted && unit == r'\') {
        isEscaped = true;
      } else if (unit == '"') {
        isQuoted = !isQuoted;
      } else if (unit == ';' && !isQuoted) {
        segments.add(current.toString());
        current.clear();
        continue;
      }
      current.write(unit);
    }
    segments.add(current.toString());
    return isQuoted ? null : segments;
  }

  static (String, String)? _parameter(String segment) {
    final index = segment.indexOf('=');
    if (index < 0) return null;
    final name = segment.substring(0, index).trim().toLowerCase();
    final value = _value(segment.substring(index + 1).trim());
    return name.isEmpty || value == null ? null : (name, value);
  }

  // A token as written, or a quoted string without its quotes and escapes;
  // null for text after the closing quote.
  static String? _value(String text) {
    if (!text.startsWith('"')) return text;
    final value = StringBuffer();
    var isEscaped = false;
    for (var i = 1; i < text.length; i++) {
      final unit = text[i];
      if (isEscaped) {
        value.write(unit);
        isEscaped = false;
      } else if (unit == r'\') {
        isEscaped = true;
      } else if (unit == '"') {
        return text.substring(i + 1).trim().isEmpty ? value.toString() : null;
      } else {
        value.write(unit);
      }
    }
    return null;
  }
}
