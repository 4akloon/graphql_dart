import 'package:typed_graphql/typed_graphql.dart';

import 'secret_redactor.dart';

/// Prints diagnostics for a terminal.
///
/// {@category codegen}
final class const DiagnosticPrinter([
  /// Hides secrets and escapes control characters in what is printed.
  final SecretRedactor redactor = const SecretRedactor([]),
]) {
  /// Creates the printer.
  this;

  /// [diagnostic] as `path:line:col: severity GQLnnn: message`, then the
  /// excerpt of its span and a note per related span; without a span,
  /// `severity GQLnnn: message`. Secrets are hidden and control characters
  /// escaped, so a server's text cannot drive the terminal.
  String print(Diagnostic diagnostic) {
    final lines = <String>[diagnostic.toString()];
    final span = diagnostic.span;
    if (span != null) lines.add(span.excerpt);
    for (final place in diagnostic.related) {
      lines.add('$place: note: related');
    }
    return redactor.escapeTerminal(redactor.redact(lines.join('\n')));
  }
}
