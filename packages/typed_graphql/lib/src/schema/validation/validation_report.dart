import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source_span.dart';

/// Collects the errors of one schema validation in the order the rules
/// report them, as graphql-js's `validateSchema` does, up to a
/// [DiagnosticSink]'s limit.
///
/// The elements of a schema may come from several sources, so the errors
/// are not sorted by offset: the rules walk the schema in declaration
/// order, which is deterministic.
final class ValidationReport {
  /// Creates an empty report.
  ValidationReport();

  final DiagnosticSink _sink = DiagnosticSink();

  /// Whether an error was reported.
  bool get hasErrors => _sink.hasErrors;

  /// Whether the limit was reached: later errors are dropped, so a rule
  /// may stop and skip building the text of an error that nobody reads.
  bool get isFull => _sink.isFull;

  /// The errors, in report order.
  List<Diagnostic> get diagnostics => _sink.diagnostics;

  /// Reports an error at the first of [spans], with the others as related
  /// places; null spans are left out (an element built in code has none).
  void error(
    DiagnosticCode code,
    String message, [
    List<SourceSpan?> spans = const [],
  ]) {
    final places = [for (final span in spans) ?span];
    _sink.report(
      Diagnostic(
        code,
        .error,
        message,
        span: places.firstOrNull,
        related: places.skip(1).toList(),
      ),
    );
  }
}
