@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

// The core's documentation suite owns the snippet finder and runner; this
// suite shares them instead of keeping a copy that could drift.
import '../../../typed_graphql/test/doc/doc_files.dart';
import '../../../typed_graphql/test/doc/doc_snippet.dart';
import '../../../typed_graphql/test/doc/snippet_runner.dart';

/// Every program in the guide, a fence tagged `dart`, is complete: it
/// compiles, runs, and prints what the text after it says (R11.2).
void main() {
  final snippets = [
    for (final MapEntry(key: path, value: markdown)
        in const DocFiles().guides().entries)
      ...const DocSnippets().of(path, markdown),
  ];
  // `late`: the runner needs the package configuration, which only
  // `Isolate.packageConfig` (a Future) gives, and `setUpAll` sets it before
  // any test reads it.
  late final SnippetRunner runner;
  Directory? directory;

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

  final skip = SnippetRunner.isAvailable
      ? null
      : 'needs the dart tool, not a compiled test';

  test('the guide holds at least one program', () {
    expect(snippets, isNotEmpty);
  });

  test('every program is formatted as dart format prints it', () async {
    expect(await runner.unformattedPlaces(snippets), isEmpty);
  }, skip: skip);

  for (final (index, snippet) in snippets.indexed) {
    test('${snippet.place} runs', () async {
      final result = await runner.run(snippet, 'snippet_$index');
      expect(result.exitCode, 0, reason: result.errors);
    }, skip: skip);

    if (snippet.expectedOutput case final expected?) {
      test('${snippet.place} prints what the guide says', () async {
        final result = await runner.run(snippet, 'snippet_${index}_output');
        expect(result.output, expected.trimRight());
      }, skip: skip);
    }
  }
}
