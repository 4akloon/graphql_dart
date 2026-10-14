@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../packages/typed_graphql/test/doc/markdown_links.dart';
import 'workspace_packages.dart';

/// Every relative link of the pages an agent lands on leads somewhere
/// (docs/discovery.md, "Links"); the checker is the core's documentation
/// suite's, shared.
void main() {
  const links = MarkdownLinks();
  final readmes = [
    for (final folder in Directory('packages').listSync())
      if (folder is Directory) '${folder.path.replaceAll(r'\', '/')}/README.md',
  ].where((path) => File(path).existsSync()).toList()..sort();
  final pages = ['README.md', 'docs/discovery.md', ...readmes];

  for (final path in pages) {
    final markdown = File(path).readAsStringSync();
    for (final MarkdownLink(:line, :target) in links.relativeIn(markdown)) {
      test('$path:$line -> $target', () {
        expect(links.problemOf(path, target), isNull);
      });
    }
  }

  // pub.dev publishes the package folder alone: a link out of it works on
  // GitHub but not in the archive. Write such a link as an absolute URL.
  for (final package in const WorkspacePackages().publishable()) {
    final folder = 'packages/${package.name}/';
    final path = '${folder}README.md';
    final markdown = File(path).readAsStringSync();
    for (final MarkdownLink(:line, :target) in links.relativeIn(markdown)) {
      test('$path:$line -> $target stays in the package', () {
        expect(Uri.parse(path).resolve(target).path, startsWith(folder));
      });
    }
  }
}
