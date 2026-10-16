import 'context_entry.dart';

/// The HTTP status and headers of the answer a result came from, written
/// by the HTTP and SSE links on the result's context.
///
/// {@category link}
final class HttpResponseInfo(
  /// The HTTP status code.
  final int statusCode, {
  Map<String, String> headers = const {},
}) extends ContextEntry {
  /// Creates the entry; [headers] is copied.
  this;

  /// The answer's headers, names in lower case.
  final Map<String, String> headers = Map.unmodifiable(headers);

  @override
  String toString() => 'HttpResponseInfo($statusCode)';
}
