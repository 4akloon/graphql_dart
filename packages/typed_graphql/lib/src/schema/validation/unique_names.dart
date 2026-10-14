import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/source_span.dart';
import 'validation_report.dart';

/// The rule that the elements of one list have different names: types,
/// directives, the fields of a type, the arguments of a field.
///
/// The builder drops repeats in SDL, so only a schema built in code has
/// any; the messages are the builder's.
final class UniqueNames(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rule.
  this;

  /// Reports each of [named] whose name an earlier one has, with
  /// [message] of the name, at the repeat and related to the first.
  void check(
    List<(String, SourceSpan?)> named,
    DiagnosticCode code,
    String Function(String name) message,
  ) {
    // Only for lookups; the errors follow the order of [named].
    final firstSpans = <String, SourceSpan?>{};
    for (final (name, span) in named) {
      if (firstSpans.containsKey(name)) {
        report.error(code, message(name), [span, firstSpans[name]]);
      } else {
        firstSpans[name] = span;
      }
    }
  }
}
