@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_project.dart';

void main() {
  late CliProject project;
  setUp(() => project = CliProject());
  tearDown(() => project.delete());

  String settings() {
    final lines = project.file('typed_graphql.yaml').readAsLinesSync();
    return lines.join('\n');
  }

  void documents(String list) => project
      .file('typed_graphql.yaml')
      .writeAsStringSync('${settings()}\ndocuments: [$list]\n');

  test('an invalid documents pattern is GQL501', () async {
    documents('"lib/[.graphql"');
    expect(await project.run(['generate']), 1);
    expect(
      project.err.toString(),
      startsWith("error GQL501: The documents pattern 'lib/[.graphql' "),
    );
  });

  test('a symbolic link to a document is not followed', () async {
    final outside = File('${project.directory.path}/outside.txt')
      ..writeAsStringSync('query Outside { __typename }');
    Link('${project.directory.path}/lib/link.graphql').createSync(outside.path);
    expect(await project.run(['generate']), 0);
    expect(project.file('lib/link.graphql.dart').existsSync(), isFalse);
  });

  test('an unreadable document is GQL510', () async {
    project.file('lib/bad.graphql').writeAsBytesSync([0xff, 0xfe]);
    expect(await project.run(['generate']), 1);
    expect(
      project.err.toString(),
      startsWith("error GQL510: Cannot read 'lib/bad.graphql': "),
    );
  });

  test('check with only a warning exits 0 and prints it', () async {
    for (final path in ['user', 'user_mutations', 'user_subscriptions']) {
      project.file('lib/$path.graphql').deleteSync();
    }
    await project.run(['generate']);
    expect(await project.run(['check']), 0);
    expect(project.err.toString(), contains('warning GQL506'));
    expect(project.out.toString(), 'Up to date.\n');
  });

  test('check ignores a generated file whose document was removed', () async {
    await project.run(['generate']);
    project.file('lib/user_mutations.graphql').deleteSync();
    await project.run(['generate']);
    expect(await project.run(['check']), 0);
    expect(
      project.file('lib/user_mutations.graphql.dart').existsSync(),
      isTrue,
    );
  });
}
