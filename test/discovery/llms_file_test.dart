@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../packages/typed_graphql/test/doc/markdown_links.dart';
import 'llms_text.dart';
import 'readme_outline.dart';
import 'workspace_packages.dart';

/// `llms.txt` at the repository root is the map an agent reads first
/// (docs/discovery.md, "llms.txt"): its shape is llmstxt.org's, and every
/// link leads to a file of this repository.
void main() {
  const prefix = 'https://github.com/4akloon/graphql_dart/blob/main/';
  const links = MarkdownLinks();
  final text = File('llms.txt').readAsStringSync();
  final llms = LlmsText(text);
  final packages = const WorkspacePackages().publishable();

  test('has one title, typed_graphql', () {
    expect(llms.titles, ['typed_graphql']);
  });

  test('has one summary', () {
    expect(llms.summaries, hasLength(1));
  });

  test('has the sections Packages, Guides and Reference', () {
    expect(llms.sections, ['Packages', 'Guides', 'Reference']);
  });

  test('has only absolute links', () {
    expect(links.relativeIn(text), isEmpty);
  });

  for (final section in llms.sections) {
    for (final entry in llms.entriesOf(section)) {
      test('${entry.url} is a file of the repository', () {
        expect(entry.url, startsWith(prefix));
        final target = Uri.parse(entry.url.substring(prefix.length));
        expect(File(target.path).existsSync(), isTrue, reason: target.path);
        if (target.fragment.isEmpty) return;
        final markdown = File(target.path).readAsStringSync();
        expect(links.anchorsIn(markdown), contains(target.fragment));
      });

      test('${entry.title} has a description', () {
        expect(entry.description, isNotEmpty);
      });
    }
  }

  test('lists every publishable package', () {
    expect(
      llms.entriesOf('Packages').map((entry) => entry.title),
      packages.map((package) => package.name),
    );
  });

  for (final entry in llms.entriesOf('Packages')) {
    test('gives the status of ${entry.title} as its README does', () {
      final readme = File('packages/${entry.title}/README.md');
      final status = ReadmeOutline(readme.readAsStringSync()).status;
      expect(entry.description, startsWith('$status;'));
    });
  }

  test('lists every guide of the core', () {
    final guides = [
      for (final file in Directory('packages/typed_graphql/doc').listSync())
        if (file.uri.pathSegments.last case final name
            when name.endsWith('.md'))
          '${prefix}packages/typed_graphql/doc/$name',
    ];
    expect(
      llms.entriesOf('Guides').map((entry) => entry.url),
      containsAll(guides),
    );
  });

  test('lists the example program of the core', () {
    expect(
      llms.entriesOf('Guides').map((entry) => entry.url),
      contains('${prefix}packages/typed_graphql/example/example.dart'),
    );
  });
}
