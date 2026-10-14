import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source_span.dart';
import '../../language/ast/node.dart';
import 'node_spans.dart';

/// Collects the errors of one build and gives them in document order.
///
/// The builder finds problems pass by pass (definitions, then extensions),
/// so it reports out of order; [diagnostics] sorts them by the offset of
/// the node they point at, as graphql-js's single-pass SDL rules report,
/// and only then applies a [DiagnosticSink]'s limit.
final class BuildReport(
  /// Gives each error the span of its node.
  final NodeSpans spans,
) {
  /// Creates an empty report.
  this;

  final List<(int, Diagnostic)> _errors = [];

  /// Whether an error was reported.
  bool get hasErrors => _errors.isNotEmpty;

  /// Reports an error at [at], with the span of what it repeats or
  /// contradicts as [related].
  void error(
    DiagnosticCode code,
    String message,
    Node at, {
    SourceSpan? related,
  }) {
    final diagnostic = Diagnostic(
      code,
      .error,
      message,
      span: spans.of(at),
      related: [?related],
    );
    _errors.add((at.start, diagnostic));
  }

  /// The errors by offset, report order kept at one offset, cut at the
  /// sink's limit; a method because it sorts on every call.
  List<Diagnostic> diagnostics() {
    final ordered = [
      for (final (index, (offset, diagnostic)) in _errors.indexed)
        (offset, index, diagnostic),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    final sink = DiagnosticSink();
    for (final (_, _, diagnostic) in ordered) {
      sink.report(diagnostic);
    }
    return sink.diagnostics;
  }
}
