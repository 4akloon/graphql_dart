import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('{ a b c d }');

  Diagnostic error(int offset) => Diagnostic(
    .diagnosticLimitReached,
    .error,
    'error at $offset',
    span: SourceSpan(source, offset, offset + 1),
  );

  Diagnostic warning(int offset) => Diagnostic(
    .diagnosticLimitReached,
    .warning,
    'warning at $offset',
    span: SourceSpan(source, offset, offset + 1),
  );

  test('starts empty', () {
    final sink = DiagnosticSink();
    expect(sink.diagnostics, isEmpty);
    expect(sink.hasErrors, isFalse);
    expect(sink.isFull, isFalse);
    expect(sink.maxErrors, DiagnosticSink.defaultMaxErrors);
  });

  test('keeps diagnostics in the order they were reported', () {
    final sink = DiagnosticSink()
      ..report(error(6))
      ..report(warning(2))
      ..report(error(4));
    expect(
      [for (final d in sink.diagnostics) d.message],
      [
        'error at 6',
        'warning at 2',
        'error at 4',
      ],
    );
  });

  test('hasErrors ignores warnings', () {
    final sink = DiagnosticSink()..report(warning(2));
    expect(sink.hasErrors, isFalse);
    sink.report(error(4));
    expect(sink.hasErrors, isTrue);
  });

  test('replaces the first error over the limit with GQL000 and stops', () {
    final sink = DiagnosticSink(maxErrors: 2)
      ..report(error(2))
      ..report(error(4))
      ..report(error(6))
      ..report(error(8))
      ..report(warning(8));
    expect(sink.isFull, isTrue);
    expect(sink.diagnostics, hasLength(3));
    final limit = sink.diagnostics.last;
    expect(limit.code, DiagnosticCode.diagnosticLimitReached);
    expect(limit.severity, DiagnosticSeverity.error);
    expect(limit.span, SourceSpan(source, 6, 7));
    expect(limit.message, contains('limit of 2'));
  });

  test('does not count warnings toward the limit', () {
    final sink = DiagnosticSink(maxErrors: 1)
      ..report(warning(2))
      ..report(warning(4))
      ..report(error(6))
      ..report(warning(8));
    expect(sink.isFull, isFalse);
    expect(sink.diagnostics, hasLength(4));
  });

  test('gives a copy that cannot be modified', () {
    final sink = DiagnosticSink()..report(error(2));
    final seen = sink.diagnostics;
    sink.report(error(4));
    expect(seen, hasLength(1));
    expect(() => seen.add(error(6)), throwsUnsupportedError);
  });

  test('rejects a limit below 1', () {
    expect(() => DiagnosticSink(maxErrors: 0), throwsArgumentError);
  });
}
