/// An exception of the transport with the query strings removed from its
/// text, since a `GET` request carries the variables in its URL and
/// `package:http` prints the full URL in its exceptions.
final class RedactedError implements Exception {
  /// Hides the query string of every URL in the text of [cause].
  RedactedError(Object cause)
    : message = '$cause'.replaceAllMapped(_url, (match) => match[1]!);

  /// The text of the original exception without query strings.
  final String message;

  static final RegExp _url = RegExp(
    r'''([a-z][a-z0-9+.-]*://[^\s?"'#]*)\?[^\s"'#]*''',
  );

  @override
  String toString() => message;
}
