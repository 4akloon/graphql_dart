/// Keeps secrets and terminal control characters out of what the command line
/// prints.
///
/// {@category codegen}
final class const SecretRedactor(
  /// The texts to hide, such as expanded header values; an empty one is
  /// ignored.
  final List<String> secrets,
) {
  /// Creates a redactor for [secrets].
  this;

  static final RegExp _control = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _keptControl = RegExp(r'[\x00-\x08\x0B-\x1F\x7F]');

  /// [text] with every secret replaced by `***`, longest first so that a
  /// secret inside another is hidden whole.
  String redact(String text) {
    final ordered = [
      for (final secret in secrets)
        if (secret.isNotEmpty) secret,
    ]..sort((a, b) => b.length.compareTo(a.length));
    var result = text;
    for (final secret in ordered) {
      result = result.replaceAll(secret, '***');
    }
    return result;
  }

  /// [text] on one line: every control character, line breaks included,
  /// becomes a `\uXXXX` escape.
  String escapeAll(String text) => _escape(text, _control);

  /// [text] with the control characters that could drive a terminal (all but
  /// the tab and the line feed) escaped as `\uXXXX`.
  String escapeTerminal(String text) => _escape(text, _keptControl);

  /// [url] as it may be printed: without user information, query and
  /// fragment, which may hold a token.
  String displayUrl(Uri url) => Uri(
    scheme: url.scheme,
    host: url.host,
    port: url.hasPort ? url.port : null,
    path: url.path,
  ).toString();

  String _escape(String text, RegExp pattern) => text.replaceAllMapped(
    pattern,
    (match) =>
        '\\u${match.group(0)!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
  );
}
