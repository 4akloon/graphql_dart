@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'readme_outline.dart';
import 'workspace_packages.dart';

/// The README opening an agent reads on pub.dev says what the package does
/// and whether to use it (docs/discovery.md, "README").
void main() {
  final core = ReadmeOutline(
    File('packages/typed_graphql/README.md').readAsStringSync(),
  );

  group('typed_graphql', () {
    test('opens with a paragraph that names GraphQL and Dart', () {
      expect(core.opening.first, allOf(contains('GraphQL'), contains('Dart')));
    });

    test('opens with the task in the words of the first query', () {
      expect(core.opening.first, startsWith('**Parse'));
    });

    test('keeps the status banner right under the opening paragraph', () {
      expect(core.opening[1], startsWith('> **Status:'));
    });

    test('has "Should I use this?" right after Install', () {
      final headings = core.headings;
      expect(headings, contains('Install'));
      expect(
        headings.indexOf('Should I use this?'),
        headings.indexOf('Install') + 1,
      );
    });

    for (final label in const [
      'Use it when',
      'You do not need it when',
      'What it replaces',
      'Which package',
    ]) {
      test('answers "Should I use this?" with "$label"', () {
        expect(core.section('Should I use this?'), contains('**$label**'));
      });
    }
  });

  // The spec forbids naming, ranking or judging a third-party package in
  // the repository's own texts. CLAUDE.md and the roadmap may name the
  // package this project does not depend on, so they are not scanned.
  final scanned = {
    'README.md': File('README.md').readAsStringSync(),
    'llms.txt': File('llms.txt').readAsStringSync(),
    'docs/discovery.md': File('docs/discovery.md').readAsStringSync(),
    for (final package in const WorkspacePackages().publishable()) ...{
      'packages/${package.name}/README.md': File(
        'packages/${package.name}/README.md',
      ).readAsStringSync(),
      'packages/${package.name}/pubspec.yaml description':
          package.field('description') ?? '',
    },
  };
  for (final MapEntry(:key, :value) in scanned.entries) {
    test('$key names no third-party GraphQL package', () {
      final text = value.toLowerCase();
      // A name inside `typed_graphql_codegen` is ours, so it must start a word.
      for (final name in const [
        'package:gql',
        'package:graphql',
        'gql_',
        'graphql_flutter',
        'ferry',
        'artemis',
        'graphql_codegen',
      ]) {
        expect(text, isNot(contains(RegExp('(?<![a-z_])$name'))), reason: name);
      }
    });
  }

  // A skeleton is a package whose library exports nothing: an agent that lands on it must not try it.
  for (final package in const WorkspacePackages().publishable()) {
    final path = 'packages/${package.name}/README.md';
    final outline = ReadmeOutline(File(path).readAsStringSync());
    final library = File(
      'packages/${package.name}/lib/${package.name}.dart',
    ).readAsStringSync();
    if (library.contains(RegExp('^export ', multiLine: true))) continue;
    test('$path says it is not usable yet, under the status banner', () {
      final opening = outline.opening;
      final banner = opening.indexWhere(
        (paragraph) => paragraph.startsWith('> **Status:'),
      );
      expect(
        opening.elementAtOrNull(banner + 1),
        startsWith('**Not usable yet.**'),
      );
    });
  }
}
