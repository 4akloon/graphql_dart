import 'package:typed_graphql/typed_graphql.dart';

/// Prints diagnostics for a terminal.
///
/// {@category codegen}
final class const DiagnosticPrinter() {
  /// Creates the printer.
  this;

  /// [diagnostic] as `path:line:col: severity GQLnnn: message`, then the
  /// excerpt of its span and a note per related span; without a span,
  /// `severity GQLnnn: message`.
  String print(Diagnostic diagnostic) {
    final lines = <String>[diagnostic.toString()];
    final span = diagnostic.span;
    if (span != null) lines.add(span.excerpt);
    for (final place in diagnostic.related) {
      lines.add('$place: note: related');
    }
    return lines.join('\n');
  }
}
