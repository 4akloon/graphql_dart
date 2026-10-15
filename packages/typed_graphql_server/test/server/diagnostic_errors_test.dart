import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/server/diagnostic_errors.dart';

void main() {
  const errors = DiagnosticErrors();
  final error = Diagnostic(
    DiagnosticCode.values.first,
    DiagnosticSeverity.error,
    'an error',
  );
  final warning = Diagnostic(
    DiagnosticCode.values.first,
    DiagnosticSeverity.warning,
    'a warning',
  );

  test('drops a warning next to an error', () {
    expect(errors.of([warning, error]).map((e) => e.message), ['an error']);
  });

  test('reports warnings when there is no error', () {
    expect(errors.of([warning]).map((e) => e.message), ['a warning']);
  });
}
