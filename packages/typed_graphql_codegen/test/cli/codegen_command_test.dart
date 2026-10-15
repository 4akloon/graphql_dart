@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_project.dart';

final bool _isDartTool =
    p.basenameWithoutExtension(Platform.resolvedExecutable) == 'dart';

void main() {
  late CliProject project;
  setUp(() => project = CliProject());
  tearDown(() => project.delete());

  const generated = 'lib/user.graphql.dart';

  test('generate writes the files of the goldens', () async {
    expect(await project.run(['generate']), 0);
    expect(project.out.toString(), 'Wrote 6 files.\n');
    for (final golden in Directory(
      'test/goldens/operations/output',
    ).listSync(recursive: true).whereType<File>()) {
      final path = golden.path.substring(
        'test/goldens/operations/output/'.length,
        golden.path.length - '.golden'.length,
      );
      expect(project.file(path).readAsStringSync(), golden.readAsStringSync());
    }
  });

  test('a generate that writes one file says so in the singular', () async {
    await project.run(['generate']);
    project.file(generated).writeAsStringSync('// edited\n');
    expect(await project.run(['generate']), 0);
    expect(project.out.toString(), 'Wrote 1 file.\n');
  });

  test('a second generate writes nothing', () async {
    await project.run(['generate']);
    expect(await project.run(['generate']), 0);
    expect(project.out.toString(), 'Nothing to write.\n');
  });

  test('check after generate is clean', () async {
    await project.run(['generate']);
    expect(await project.run(['check']), 0);
    expect(project.out.toString(), 'Up to date.\n');
  });

  test('check reports a missing file and writes nothing', () async {
    expect(await project.run(['check']), 1);
    expect(
      project.err.toString(),
      contains(
        "error GQL509: The generated file 'build/persisted_operations.json' "
        'is out of date; run `dart run typed_graphql_codegen generate`.',
      ),
    );
    expect(project.file(generated).existsSync(), isFalse);
  });

  test('check reports an edited file and does not rewrite it', () async {
    await project.run(['generate']);
    project.file(generated).writeAsStringSync('// edited\n');
    expect(await project.run(['check']), 1);
    expect(
      project.err.toString(),
      "error GQL509: The generated file '$generated' is out of date; run "
      '`dart run typed_graphql_codegen generate`.\n',
    );
    expect(project.file(generated).readAsStringSync(), '// edited\n');
  });

  test('a missing schema file is GQL510', () async {
    project.file('schema.graphql').deleteSync();
    expect(await project.run(['generate']), 1);
    expect(
      project.err.toString(),
      startsWith("error GQL510: Cannot read 'schema.graphql': "),
    );
  });

  test('a missing configuration is GQL510', () async {
    expect(await project.run(['generate', '--config', 'other.yaml']), 1);
    expect(
      project.err.toString(),
      startsWith("error GQL510: Cannot read 'other.yaml': "),
    );
  });

  test('a syntax error prints its place and excerpt', () async {
    project.file('lib/x.graphql').writeAsStringSync('query Q {\n');
    expect(await project.run(['generate']), 1);
    expect(project.err.toString(), startsWith('lib/x.graphql:2:1: error GQL'));
    expect(project.err.toString(), contains('1 | query Q {'));
  });

  test('a warning alone exits 0', () async {
    for (final path in [
      'user',
      'stats',
      'user_mutations',
      'user_subscriptions',
    ]) {
      project.file('lib/$path.graphql').deleteSync();
    }
    expect(await project.run(['generate']), 0);
    expect(project.err.toString(), contains('warning GQL506'));
  });

  test('a document outside the glob is ignored', () async {
    project.file('other/z.graphql').createSync(recursive: true);
    project.file('other/z.graphql').writeAsStringSync('query {');
    expect(await project.run(['generate']), 0);
    expect(project.file('other/z.graphql.dart').existsSync(), isFalse);
  });

  test('generate never deletes a stale generated file', () async {
    await project.run(['generate']);
    project.file('lib/user_mutations.graphql').deleteSync();
    expect(await project.run(['generate']), 0);
    expect(
      project.file('lib/user_mutations.graphql.dart').existsSync(),
      isTrue,
    );
  });

  // Under `--compiler exe` the resolved executable is the test binary.
  test('the executable passes the exit code to the process', () async {
    final result = Process.runSync(Platform.resolvedExecutable, [
      'run',
      '${Directory.current.path}/bin/typed_graphql_codegen.dart',
      'check',
      '--config',
      '${project.directory.path}/typed_graphql.yaml',
    ]);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('GQL509'));
  }, skip: _isDartTool ? false : 'the tests do not run on the dart tool');
}
