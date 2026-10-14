import 'diagnostic.dart';
import 'diagnostic_code.dart';

/// Collects the diagnostics of one parse, validation or decoding run, in
/// the order they are reported.
///
/// The lexer, the parser and the validation rules take a sink through
/// their constructor and report into it; the public API turns
/// [diagnostics] into a result (spec §2). The order is never changed:
/// graphql-js reports in the same order, and the ported suites compare
/// lists.
///
/// A sink keeps at most [maxErrors] errors; warnings do not count. The
/// next error adds one [DiagnosticCode.diagnosticLimitReached] error at its
/// place instead, [isFull] becomes true and every later report is ignored,
/// as graphql-js's `maxErrors` aborts validation.
final class DiagnosticSink {
  /// Creates an empty sink that keeps at most [maxErrors] errors.
  DiagnosticSink({this.maxErrors = defaultMaxErrors}) {
    if (maxErrors < 1) {
      throw ArgumentError.value(maxErrors, 'maxErrors', 'must be at least 1');
    }
  }

  /// The default of [maxErrors]: graphql-js's `maxErrors` for validation.
  static const int defaultMaxErrors = 100;

  /// The most errors this sink keeps before it reports the limit.
  final int maxErrors;

  final List<Diagnostic> _diagnostics = [];
  int _errorCount = 0;
  bool _isFull = false;

  /// Whether the limit was reached: later reports are ignored, so the run
  /// may stop.
  bool get isFull => _isFull;

  /// Whether an error was reported.
  bool get hasErrors => _errorCount > 0;

  /// The diagnostics in the order they were reported, the limit error last
  /// when [isFull]; a copy that cannot be modified.
  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Adds [diagnostic], unless the sink is full.
  void report(Diagnostic diagnostic) {
    if (_isFull) {
      return;
    }
    if (diagnostic.isError && _errorCount == maxErrors) {
      _isFull = true;
      _diagnostics.add(_limitReached(diagnostic));
      return;
    }
    if (diagnostic.isError) {
      _errorCount++;
    }
    _diagnostics.add(diagnostic);
  }

  /// The error that stands for [dropped] and every error after it.
  Diagnostic _limitReached(Diagnostic dropped) => Diagnostic(
    .diagnosticLimitReached,
    .error,
    'Too many errors: the limit of $maxErrors was reached and the rest are '
    'not reported.',
    span: dropped.span,
  );
}
