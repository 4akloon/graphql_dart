@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main() {
  const root = 'example';
  String read(String path) => File('$root/$path').readAsStringSync();

  final parsed = CodegenConfig.parse(
    read('typed_graphql.yaml'),
    path: 'typed_graphql.yaml',
  );
  final config = (parsed as ConfigSuccess).config;
  final result = ClientGenerator(config).generate(
    schema: ProjectFile('schema.graphql', read('schema.graphql')),
    documents: [ProjectFile('lib/user.graphql', read('lib/user.graphql'))],
  );

  test('the example generates without diagnostics', () {
    expect(result.diagnostics, isEmpty);
  });

  test('the generated files are the two checked in', () {
    expect(
      [for (final file in result.files) file.path],
      ['lib/schema.graphql.dart', 'lib/user.graphql.dart'],
    );
  });

  for (final file in result.files) {
    test('${file.path} equals the checked-in file', () {
      expect(file.text, read(file.path));
    });
  }
}
