import 'package:typed_graphql/typed_graphql.dart';

/// Replaces `${NAME}` in header values by environment variables.
///
/// Only the exact form `${NAME}` with `NAME` of `[A-Za-z_][A-Za-z0-9_]*` is a
/// reference; `$$`, a lone `$` and a `${` without `}` stay as written, so
/// there is no escape syntax. A value is expanded once: the text an
/// environment variable holds is not expanded again.
///
/// {@category codegen}
final class const HeaderExpander(
  /// The environment variables by name.
  final Map<String, String> environment,
) {
  /// Creates an expander over [environment].
  this;

  static final RegExp _reference = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
  static final RegExp _control = RegExp(r'[\x00-\x08\x0A-\x1F\x7F]');

  /// Expands every value of [headers]; the problems (`GQL501`) never hold a
  /// header value, and a header with a problem is left out of the result.
  ({Map<String, String> headers, List<Diagnostic> problems}) expand(
    Map<String, String> headers,
  ) {
    final expanded = <String, String>{};
    final problems = <Diagnostic>[];
    for (final MapEntry(:key, :value) in headers.entries) {
      final missing = _missing(value);
      if (missing != null) {
        problems.add(
          _problem(
            "The header '$key' uses the environment variable '$missing', "
            'which is not set.',
          ),
        );
        continue;
      }
      final text = value.replaceAllMapped(
        _reference,
        (match) => environment[match.group(1)]!,
      );
      if (_control.hasMatch(text)) {
        problems.add(
          _problem(
            "The value of header '$key' must not have a control character "
            'after its environment variables are expanded.',
          ),
        );
        continue;
      }
      expanded[key] = text;
    }
    return (headers: expanded, problems: problems);
  }

  String? _missing(String value) {
    for (final match in _reference.allMatches(value)) {
      final name = match.group(1)!;
      if (!environment.containsKey(name)) return name;
    }
    return null;
  }

  Diagnostic _problem(String message) =>
      Diagnostic(.invalidConfig, .error, message);
}
