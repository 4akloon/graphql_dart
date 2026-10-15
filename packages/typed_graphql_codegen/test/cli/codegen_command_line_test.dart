@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/cli/codegen_command_line.dart';

import '../support/cli_project.dart';

void main() {
  late CliProject project;
  setUp(() => project = CliProject());
  tearDown(() => project.delete());

  test('no command is a usage error', () {
    expect(project.run([]), 64);
    expect(project.err.toString(), startsWith('Missing command.\nUsage:'));
  });

  test('an unknown command is a usage error', () {
    expect(project.run(['build']), 64);
    expect(project.err.toString(), contains('Unknown command "build".'));
  });

  test('an unknown option is a usage error', () {
    expect(project.run(['generate', '--nope']), 64);
    expect(project.err.toString(), contains('Could not find an option'));
  });

  test('--help prints the usage and succeeds', () {
    expect(project.run(['--help']), 0);
    expect(project.out.toString(), '${const CodegenCommandLine().usage}\n');
    expect(project.err.toString(), isEmpty);
  });
}
