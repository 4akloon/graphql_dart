@TestOn('vm')
library;

import 'package:test/test.dart';

import 'doc_files.dart';
import 'markdown_links.dart';

/// Every relative link of the guides and READMEs leads somewhere (R11.1,
/// R11.2).
void main() {
  const links = MarkdownLinks();
  final files = const DocFiles().all();

  test('no guide links to another file, which dartdoc would break', () {
    for (final MapEntry(key: path, value: markdown)
        in const DocFiles().guides().entries) {
      expect(links.relativeIn(markdown), isEmpty, reason: path);
    }
  });

  group('links resolve', () {
    for (final MapEntry(key: path, value: markdown) in files.entries) {
      for (final MarkdownLink(:line, :target) in links.relativeIn(markdown)) {
        test('$path:$line -> $target', () {
          expect(links.problemOf(path, target), isNull);
        });
      }
    }
  });
}
