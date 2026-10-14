import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/build_report.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('scalar A scalar B');
  const a = Name('A', start: 7, end: 8);
  const b = Name('B', start: 16, end: 17);

  test('gives the errors in document order, not report order', () {
    final report = BuildReport(NodeSpans(source))
      ..error(DiagnosticCode.executableDefinitionInSchema, 'second', b)
      ..error(DiagnosticCode.executableDefinitionInSchema, 'first', a);
    expect(report.diagnostics().map((diagnostic) => diagnostic.message), [
      'first',
      'second',
    ]);
  });

  test('keeps report order between errors at one offset', () {
    final report = BuildReport(NodeSpans(source))
      ..error(DiagnosticCode.executableDefinitionInSchema, 'one', a)
      ..error(DiagnosticCode.executableDefinitionInSchema, 'two', a);
    expect(report.diagnostics().map((diagnostic) => diagnostic.message), [
      'one',
      'two',
    ]);
  });

  test('points an error at its node, with the related span', () {
    final related = SourceSpan(source, 0, 8);
    final report = BuildReport(NodeSpans(source))
      ..error(
        DiagnosticCode.executableDefinitionInSchema,
        'here',
        b,
        related: related,
      );
    final diagnostic = report.diagnostics().single;
    expect(diagnostic.span, SourceSpan(source, 16, 17));
    expect(diagnostic.related, [related]);
    expect(diagnostic.severity, DiagnosticSeverity.error);
  });

  test('stops after the limit of a sink, with one limit error', () {
    final report = BuildReport(NodeSpans(source));
    for (var i = 0; i < DiagnosticSink.defaultMaxErrors + 5; i++) {
      report.error(DiagnosticCode.executableDefinitionInSchema, '$i', a);
    }
    expect(
      report.diagnostics(),
      hasLength(DiagnosticSink.defaultMaxErrors + 1),
    );
    expect(
      report.diagnostics().last.code,
      DiagnosticCode.diagnosticLimitReached,
    );
  });

  test('has errors once one is reported', () {
    final report = BuildReport(NodeSpans(source));
    expect(report.hasErrors, isFalse);
    report.error(DiagnosticCode.executableDefinitionInSchema, 'one', a);
    expect(report.hasErrors, isTrue);
  });
}
