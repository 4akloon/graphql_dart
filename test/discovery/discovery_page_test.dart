@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../packages/typed_graphql/test/doc/markdown_links.dart';
import 'readme_outline.dart';

/// `docs/discovery.md` keeps the queries and the rules, and the documents
/// a maintainer reads before a change lead to it.
void main() {
  const links = MarkdownLinks();
  final page = ReadmeOutline(File('docs/discovery.md').readAsStringSync());
  final roadmap = File('docs/roadmap.md').readAsStringSync();
  // The table's rows, without its header and separator lines.
  final rows = page
      .section('Queries')
      .split('\n')
      .where((line) => line.startsWith('|'))
      .skip(2)
      .map((row) => [for (final cell in row.split('|')) cell.trim()])
      .toList();

  /// The repository paths the relative links of [markdown], written in
  /// the file at [path], point at.
  List<String> linkedFrom(String path, String markdown) => [
    for (final link in links.relativeIn(markdown))
      Uri.parse(path).resolve(link.target).path,
  ];

  test('states the rule for every sentence', () {
    expect(page.headings, contains('Say only what works today'));
  });

  test('lists queries', () {
    expect(rows, isNotEmpty);
  });

  for (final [_, query, stage, worksToday, _] in rows) {
    test('"$query" is unlocked by a stage of the roadmap', () {
      expect(roadmap, contains('| $stage |'));
    });

    test('"$query" says whether it works today', () {
      expect(worksToday, anyOf('yes', 'no'));
    });
  }

  test("the roadmap's rules for plans link to it", () {
    final rules = ReadmeOutline(roadmap).section('Rules for plans');
    expect(linkedFrom('docs/roadmap.md', rules), contains('docs/discovery.md'));
  });

  test('CONTRIBUTING.md links to it', () {
    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    expect(
      linkedFrom('CONTRIBUTING.md', contributing),
      contains('docs/discovery.md'),
    );
  });
}
