@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../../../typed_graphql/test/doc/doc_files.dart';
import '../../../typed_graphql/test/doc/doc_snippet.dart';
import '../../../typed_graphql/test/doc/snippet_runner.dart';

/// Every program in the guides and READMEs, a fence tagged `dart`, is
/// complete: it compiles, runs, and prints what the text after it says
/// (R11.2).
void main() {
  // The repository README is the server's to test; here only this package's.
  final files = const DocFiles().all()..remove('../../README.md');
  final snippets = [
    for (final MapEntry(key: path, value: markdown) in files.entries)
      ...const DocSnippets().of(path, markdown),
  ];
  final runs = <DocSnippet, Future<SnippetRun>>{};
  // `late`: the runner needs the package configuration, which only
  // `Isolate.packageConfig` (a Future) gives, and `setUpAll` sets it before
  // any test reads it. The folder is null until created, so a failure to
  // create it does not hide its cause in `tearDownAll`.
  late final SnippetRunner runner;
  Directory? directory;

  // Compiled with `--compiler exe` there is no package configuration and
  // every program is skipped, so nothing is set up or removed.
  setUpAll(() async {
    if (!SnippetRunner.isAvailable) return;
    final configuration = await Isolate.packageConfig;
    final created = Directory.systemTemp.createTempSync('typed_graphql_doc_');
    directory = created;
    runner = SnippetRunner(configuration!.toFilePath(), created);
  });
  tearDownAll(() {
    directory?.deleteSync(recursive: true);
  });

  test('every guide holds at least one program', () {
    for (final path in const DocFiles().guides().keys) {
      expect(snippets.where((snippet) => snippet.file == path), isNotEmpty);
    }
  });

  final skip = SnippetRunner.isAvailable
      ? null
      : 'needs the dart tool, not a compiled test';

  test('every program is formatted as dart format prints it', () async {
    expect(await runner.unformattedPlaces(snippets), isEmpty);
  }, skip: skip);
  for (final (index, snippet) in snippets.indexed) {
    Future<SnippetRun> run() =>
        runs.putIfAbsent(snippet, () => runner.run(snippet, 'snippet_$index'));

    test('${snippet.place} runs', () async {
      final result = await run();
      expect(result.exitCode, 0, reason: result.errors);
    }, skip: skip);

    if (snippet.expectedOutput case final expected?) {
      test('${snippet.place} prints what the guide says', () async {
        expect((await run()).output, expected.trimRight());
      }, skip: skip);
    }
  }
}
