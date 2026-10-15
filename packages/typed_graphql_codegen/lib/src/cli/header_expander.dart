import 'package:typed_graphql/typed_graphql.dart';

/// Replaces `${NAME}` in header values by environment variables.
///
/// Only the exact form `${NAME}` with `NAME` of `[A-Za-z_][A-Za-z0-9_]*` is a
/// reference; `$$`, a lone `$` and a `${` without `}` stay as written, so
/// there is no escape syntax. A value is expanded once: the text an
/// environment variable holds is not expanded again. A variable that is
/// empty counts as not set, and an expanded value must be ASCII (no control
/// character but the tab), as an HTTP header value is sent as written.
///
/// {@category codegen}
final class const HeaderExpander(
  /// The environment variables by name.
  final Map<String, String> environment,
) {
  /// Creates an expander over [environment].
  this;

  static final RegExp _reference = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
  static final RegExp _forbidden = RegExp(r'[^\x09\x20-\x7E]');

  /// Expands every value of [headers]; the problems (`GQL501`) never hold a
  /// header value, and a header with a problem is left out of the result.
  /// [secrets] are the texts a printout must hide: each expanded value and
  /// each variable's value.
  ({
    Map<String, String> headers,
    List<String> secrets,
    List<Diagnostic> problems,
  })
  expand(
    Map<String, String> headers,
  ) {
    final expanded = <String, String>{};
    final secrets = <String>[];
    final problems = <Diagnostic>[];
    for (final MapEntry(:key, :value) in headers.entries) {
      final missing = _missing(value);
      if (missing != null) {
        problems.add(
          _problem(
            "The header '$key' uses the environment variable '$missing', "
            'which is not set or is empty.',
          ),
        );
        continue;
      }
      final text = value.replaceAllMapped(
        _reference,
        (match) => environment[match.group(1)]!,
      );
      if (_forbidden.hasMatch(text)) {
        problems.add(
          _problem(
            "The value of header '$key' must be ASCII without a control "
            'character after its environment variables are expanded.',
          ),
        );
        continue;
      }
      expanded[key] = text;
      secrets.add(text);
      for (final match in _reference.allMatches(value)) {
        secrets.add(environment[match.group(1)]!);
      }
    }
    return (headers: expanded, secrets: secrets, problems: problems);
  }

  String? _missing(String value) {
    for (final match in _reference.allMatches(value)) {
      final name = match.group(1)!;
      if (environment[name]?.isEmpty ?? true) return name;
    }
    return null;
  }

  Diagnostic _problem(String message) =>
      Diagnostic(.invalidConfig, .error, message);
}
