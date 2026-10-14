@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import 'doc_snippet.dart';
import 'snippet_runner.dart';

/// The runner must fail a broken guide, or the doc tests prove nothing.
void main() {
  // `late`: `setUpAll` sets both before any test reads them; the package
  // configuration comes from a Future.
  late final Directory directory;
  late final SnippetRunner runner;

  // Compiled with `--compiler exe` there is no package configuration and
  // every test is skipped, so nothing is set up or removed.
  setUpAll(() async {
    if (!SnippetRunner.isAvailable) return;
    final configuration = await Isolate.packageConfig;
    directory = Directory.systemTemp.createTempSync('typed_graphql_runner_');
    runner = SnippetRunner(configuration!.toFilePath(), directory);
  });
  tearDownAll(() {
    if (SnippetRunner.isAvailable) directory.deleteSync(recursive: true);
  });

  final skip = SnippetRunner.isAvailable
      ? null
      : 'needs the dart tool, not a compiled test';

  DocSnippet program(String code) => DocSnippet('a.md', 1, code, null);

  test('gives the output of a program that runs', () async {
    final run = await runner.run(
      program(
        "import 'package:typed_graphql/typed_graphql.dart';\n"
        "void main() { print(Source('query { a }').body); }",
      ),
      'ok',
    );
    expect(run.exitCode, 0, reason: run.errors);
    expect(run.output, 'query { a }');
  }, skip: skip);

  test('reports a program that does not compile', () async {
    final run = await runner.run(program('void main() { missing(); }'), 'bad');
    expect(run.exitCode, isNot(0));
    expect(run.errors, contains('missing'));
  }, skip: skip);

  test('kills a program that runs past the time limit', () async {
    final impatient = SnippetRunner(
      runner.packageConfig,
      directory,
      timeLimit: const Duration(seconds: 2),
    );
    final run = await impatient.run(
      program('void main() { while (true) {} }'),
      'forever',
    );
    expect(run.hasTimedOut, isTrue);
    expect(run.errors, contains('timed out'));
  }, skip: skip);

  test('kills a program that prints without end', () async {
    final stopwatch = Stopwatch()..start();
    final run = await runner.run(
      program("void main() { while (true) { print('x' * 1000); } }"),
      'endless',
    );
    expect(run.exitCode, isNot(0));
    expect(run.hasTimedOut, isFalse);
    expect(run.errors, contains('output exceeded'));
    expect(run.output.length, lessThanOrEqualTo(SnippetRunner.outputLimit));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 30)));
  }, skip: skip);

  test('names the programs dart format would change', () async {
    final places = await runner.unformattedPlaces([
      program('void main() {\n}'),
      program('void main() {}'),
    ]);
    expect(places, ['a.md:1']);
  }, skip: skip);

  test('reports a program that throws', () async {
    final run = await runner.run(
      program("void main() { throw StateError('no'); }"),
      'throws',
    );
    expect(run.exitCode, isNot(0));
    expect(run.errors, contains('Bad state: no'));
  }, skip: skip);
}
