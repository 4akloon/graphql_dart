import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/documents/project_source_map.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main() {
  // Starts: a.graphql 0 (length 3), b.graphql 4 (length 5), c.graphql 10.
  final map = ProjectSourceMap(const [
    ProjectFile('a.graphql', 'abc'),
    ProjectFile('b.graphql', 'de\nfg'),
    ProjectFile('c.graphql', 'hi'),
  ]);

  test('the project text joins the files with line breaks', () {
    expect(map.text, 'abc\nde\nfg\nhi\n');
  });

  test('an offset in the first file maps to it', () {
    expect(map.pathAt(1), 'a.graphql');
  });

  test('an offset in the middle file maps to it', () {
    expect(map.pathAt(7), 'b.graphql');
  });

  test('an offset in the last file maps to it', () {
    expect(map.pathAt(11), 'c.graphql');
  });

  test('an offset on the joining line break belongs to the file before', () {
    expect(map.fileIndexAt(3), 0);
  });

  test('a span is translated into its file', () {
    final span = map.translate(SourceSpan(map.source, 7, 9));
    expect(['$span', span.text], ['b.graphql:2:1', 'fg']);
  });

  test('a span on the joining line break is clamped to the file', () {
    final span = map.translate(SourceSpan(map.source, 2, 4));
    expect([span.start, span.end, span.text], [2, 3, 'c']);
  });

  test('a span of another source is kept', () {
    final span = SourceSpan(Source('x', name: 'other'), 0, 1);
    expect(identical(map.translate(span), span), isTrue);
  });

  test('a diagnostic and its related spans are translated', () {
    final diagnostic = Diagnostic(
      DiagnosticCode.expectedToken,
      DiagnosticSeverity.error,
      'message',
      span: SourceSpan(map.source, 11, 12),
      related: [SourceSpan(map.source, 5, 6)],
    );
    final translated = map.translateDiagnostic(diagnostic);
    expect(
      [
        '${translated.span}',
        for (final place in translated.related) '$place',
        translated.code,
        translated.message,
      ],
      [
        'c.graphql:1:2',
        'b.graphql:1:2',
        DiagnosticCode.expectedToken,
        'message',
      ],
    );
  });

  test('a diagnostic without a span stays without one', () {
    final diagnostic = Diagnostic(
      DiagnosticCode.expectedToken,
      DiagnosticSeverity.error,
      'message',
    );
    expect(map.translateDiagnostic(diagnostic), diagnostic);
  });

  test('a span at the end of the text is clamped into the last file', () {
    final span = map.translate(SourceSpan(map.source, 13, 13));
    expect(['$span', span.start, span.end], ['c.graphql:1:3', 2, 2]);
  });

  test('a span at the first offset of a later file starts there', () {
    final span = map.translate(SourceSpan(map.source, 4, 6));
    expect(['$span', span.text], ['b.graphql:1:1', 'de']);
  });

  test('a span on the joining line break is empty at the file end', () {
    final span = map.translate(SourceSpan(map.source, 3, 4));
    expect(['$span', span.start, span.end], ['a.graphql:1:4', 3, 3]);
  });
}
