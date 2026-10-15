import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/documents/project_documents.dart';
import 'package:typed_graphql_codegen/src/documents/project_documents_result.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main() {
  ProjectDocuments read(List<ProjectFile> files) {
    final result = ProjectDocuments.read(files);
    if (result is! ProjectDocumentsRead) fail('expected success, got $result');
    return result.documents;
  }

  List<String> problems(List<ProjectFile> files) {
    final result = ProjectDocuments.read(files);
    if (result is! ProjectDocumentsUnreadable) fail('expected failure');
    return [for (final diagnostic in result.diagnostics) '$diagnostic'];
  }

  String names(int count, String prefix) =>
      [for (var i = 0; i < count; i++) '$prefix$i'].join(' ');

  const fileB = ProjectFile('b.graphql', 'fragment B on T { b }\n');
  const fileA = ProjectFile('a.graphql', 'fragment A on T { a }\n');

  test('files are sorted by path', () {
    final documents = read(const [fileB, fileA]);
    expect(
      [for (final file in documents.files) file.path],
      [
        'a.graphql',
        'b.graphql',
      ],
    );
  });

  test('the document has every definition in path order', () {
    final documents = read(const [fileB, fileA]);
    expect(
      [
        for (final definition in documents.document.definitions)
          (definition as FragmentDefinition).name.value,
      ],
      ['A', 'B'],
    );
  });

  test('a definition start maps back to its file and position', () {
    final documents = read(const [
      fileB,
      ProjectFile('a.graphql', '\n  fragment A on T { a }\n'),
    ]);
    final span = documents.sourceMap.translate(
      SourceSpan(
        documents.sourceMap.source,
        documents.document.definitions[0].start,
        documents.document.definitions[0].end,
      ),
    );
    expect('$span', 'a.graphql:2:3');
  });

  test('a syntax error is reported at its file', () {
    expect(
      problems([fileA, const ProjectFile('b.graphql', 'query {\n  a b: }')]),
      ['b.graphql:2:8: error GQL007: Expected Name, found "}".'],
    );
  });

  test('errors in two files are both reported, in path order', () {
    expect(
      problems(const [
        ProjectFile('b.graphql', '{'),
        ProjectFile('a.graphql', '{ a('),
      ]),
      [
        'a.graphql:1:5: error GQL007: Expected Name, found <EOF>.',
        'b.graphql:1:2: error GQL007: Expected Name, found <EOF>.',
      ],
    );
  });

  test('a file ending in a comment does not swallow the next file', () {
    final documents = read(const [
      ProjectFile('a.graphql', 'fragment A on T { a } # last'),
      fileB,
    ]);
    expect(documents.document.definitions, hasLength(2));
  });

  test('a file over the token limit fails with the token limit code', () {
    final text = 'query Q { ${names(15001, 'f')} }';
    final result = ProjectDocuments.read([ProjectFile('big.graphql', text)]);
    expect(
      result is ProjectDocumentsUnreadable &&
          result.diagnostics.single.code == DiagnosticCode.tokenLimitExceeded,
      isTrue,
    );
  });

  test('two files of 10000 tokens each succeed', () {
    final documents = read([
      ProjectFile('a.graphql', 'query A { ${names(9990, 'a')} }'),
      ProjectFile('b.graphql', 'query B { ${names(9990, 'b')} }'),
    ]);
    expect(documents.document.definitions, hasLength(2));
  });

  test('duplicate paths are an ArgumentError', () {
    expect(
      () => ProjectDocuments.read(const [fileA, fileA]),
      throwsArgumentError,
    );
  });

  test('no files give an empty document', () {
    expect(read(const []).document.definitions, isEmpty);
  });

  test('an empty file and a comment-only file add no definition', () {
    final documents = read(const [
      ProjectFile('0.graphql', ''),
      fileA,
      ProjectFile('c.graphql', '# nothing here\n'),
      ProjectFile('d.graphql', '\uFEFF , \n'),
    ]);
    expect(documents.document.definitions, hasLength(1));
  });

  test('only empty files give an empty document', () {
    final documents = read(const [
      ProjectFile('a.graphql', ''),
      ProjectFile('b.graphql', '# c'),
    ]);
    expect(documents.document.definitions, isEmpty);
  });

  test('a join that fails although each file parses is reported', () {
    expect(
      problems(const [
        ProjectFile('a.graphql', 'extend enum E @d'),
        ProjectFile('b.graphql', '{ user { name } }'),
      ]),
      [
        'b.graphql:1:8: error GQL007: Expected Name, found "{".',
      ],
    );
  });
}
