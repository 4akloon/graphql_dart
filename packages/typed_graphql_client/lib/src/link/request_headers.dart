import 'context_entry.dart';

/// Extra HTTP headers for one request, added by the HTTP and SSE links
/// after their own and the link's (R8.4).
///
/// Header names are case-insensitive, so they are kept in lower case.
///
/// {@category link}
final class RequestHeaders extends ContextEntry {
  /// Creates the entry for [values]; the names are lower-cased.
  RequestHeaders(Map<String, String> values)
    : values = Map.unmodifiable({
        for (final MapEntry(:key, :value) in values.entries)
          key.toLowerCase(): value,
      });

  /// The headers, names in lower case.
  final Map<String, String> values;

  /// These headers with [name] set to [value], replacing any earlier value.
  RequestHeaders withHeader(String name, String value) =>
      RequestHeaders({...values, name.toLowerCase(): value});

  @override
  String toString() => 'RequestHeaders($values)';
}
