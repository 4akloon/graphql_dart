@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import 'doc_files.dart';
import 'doc_snippet.dart';
import 'snippet_runner.dart';

/// Every program in the guides and READMEs, a fence tagged `dart`, is
/// complete: it compiles, runs, and prints what the text after it says
/// (R11.2).
void main() {
  final files = const DocFiles().all();
  final snippets = [
    for (final MapEntry(key: path, value: markdown) in files.entries)
      ...const DocSnippets().of(path, markdown),
  ];
  final runs = <DocSnippet, Future<SnippetRun>>{};
  // `late`: the folder and the runner need the package configuration,
  // which only `Isolate.packageConfig` (a Future) gives, and `setUpAll`
  // sets both before any test reads them.
  late final Directory directory;
  late final SnippetRunner runner;

  // Compiled with `--compiler exe` there is no package configuration and
  // every program is skipped, so nothing is set up or removed.
  setUpAll(() async {
    if (!SnippetRunner.isAvailable) return;
    final configuration = await Isolate.packageConfig;
    directory = Directory.systemTemp.createTempSync('typed_graphql_doc_');
    runner = SnippetRunner(configuration!.toFilePath(), directory);
  });
  tearDownAll(() {
    if (SnippetRunner.isAvailable) directory.deleteSync(recursive: true);
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
