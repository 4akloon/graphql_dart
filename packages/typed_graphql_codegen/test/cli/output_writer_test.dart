@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/cli/output_writer.dart';
import 'package:typed_graphql_codegen/src/generator/generated_file.dart';

void main() {
  late Directory directory;
  late OutputWriter writer;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('output_writer');
    writer = OutputWriter(directory.path);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  const file = GeneratedFile('lib/a.dart', 'a\n');
  const other = GeneratedFile('lib/b.dart', 'b\n');

  test('write creates the folder and leaves no temporary file', () {
    final result = writer.write([file]);
    expect(result.written, ['lib/a.dart']);
    expect(result.problems, isEmpty);
    expect(
      Directory('${directory.path}/lib').listSync().map((e) => e.path),
      ['${directory.path}/lib/a.dart'],
    );
  });

  test('a directory at an output path is GQL510 and the rest is written', () {
    Directory('${directory.path}/lib/a.dart').createSync(recursive: true);
    final result = writer.write([file, other]);
    expect(result.written, ['lib/b.dart']);
    expect(result.problems.map((d) => d.toString()), [
      startsWith("error GQL510: Cannot write 'lib/a.dart': "),
    ]);
    expect(
      [
        for (final entity in Directory('${directory.path}/lib').listSync())
          entity.path,
      ]..sort(),
      ['${directory.path}/lib/a.dart', '${directory.path}/lib/b.dart'],
    );
  });

  test('write keeps a user file named like a fixed temporary name', () {
    File('${directory.path}/lib/a.dart.tmp')
      ..createSync(recursive: true)
      ..writeAsStringSync('mine');
    writer.write([file]);
    expect(File('${directory.path}/lib/a.dart.tmp').readAsStringSync(), 'mine');
  });

  test('an output that is not UTF-8 is replaced by write', () {
    File('${directory.path}/lib/a.dart')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0xff, 0xfe]);
    final result = writer.write([file]);
    expect(result.written, ['lib/a.dart']);
    expect(File('${directory.path}/lib/a.dart').readAsStringSync(), 'a\n');
  });

  test('an output that is not UTF-8 is GQL510 for check', () {
    File('${directory.path}/lib/a.dart')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0xff, 0xfe]);
    expect(writer.outdated([file]).map((d) => d.toString()), [
      "error GQL510: Cannot read 'lib/a.dart': not a readable UTF-8 file.",
    ]);
  });

  test('a directory at an output path is GQL510 for check', () {
    Directory('${directory.path}/lib/a.dart').createSync(recursive: true);
    expect(writer.outdated([file]).map((d) => d.toString()), [
      "error GQL510: Cannot read 'lib/a.dart': not a readable UTF-8 file.",
    ]);
  });

  test('a missing file is GQL509 for check', () {
    expect(writer.outdated([file]).map((d) => d.toString()), [
      "error GQL509: The generated file 'lib/a.dart' is out of date; run "
          '`dart run typed_graphql_codegen generate`.',
    ]);
  });
}
