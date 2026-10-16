/// The answer to a `TransportRequest`: its status, headers and body.
///
/// {@category http}
final class TransportResponse({
  /// The HTTP status code.
  required final int statusCode,

  /// The body; the link listens to it once and may cancel it early.
  required final Stream<List<int>> body,
  Map<String, String> headers = const {},
}) {
  /// Creates an answer; [headers] is copied with its names in lower case.
  this;

  /// The headers, names in lower case.
  final Map<String, String> headers = Map.unmodifiable({
    for (final MapEntry(:key, :value) in headers.entries)
      key.toLowerCase(): value,
  });

  @override
  String toString() => 'TransportResponse($statusCode)';
}
