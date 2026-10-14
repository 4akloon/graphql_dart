@TestOn('vm')
library;

import 'package:test/test.dart';

import 'workspace_packages.dart';

/// The pubspec fields pub.dev shows and searches follow its rules
/// (docs/discovery.md, "Metadata"), so search finds the packages and the
/// README's relative links work on pub.dev.
void main() {
  const repository = 'https://github.com/4akloon/graphql_dart';
  // Plain text: emphasis, code, links, headings and HTML are markdown;
  // an underscore inside a name such as build_runner is not.
  final markdown = RegExp(r'[`*#<>\[\]]|(?:^|\s)_|_(?:\s|$)');
  // pub.dev: 2 to 32 characters, a-z, 0-9 and single hyphens, starting
  // with a letter and ending with a letter or digit.
  final topic = RegExp(r'^(?!.*--)[a-z][a-z0-9-]{0,30}[a-z0-9]$');
  final packages = const WorkspacePackages().publishable();

  test('reads the core and leaves out the conformance package', () {
    final names = packages.map((package) => package.name);
    expect(names, contains('typed_graphql'));
    expect(names, isNot(contains('typed_graphql_conformance')));
  });

  for (final package in packages) {
    group(package.name, () {
      final description = package.field('description') ?? '';

      test('has a description of 60 to 180 characters', () {
        expect(description.length, inInclusiveRange(60, 180));
      });

      test('has a description without markdown', () {
        expect(description, isNot(matches(markdown)));
      });

      test('has at most five topics', () {
        expect(package.topics.length, lessThanOrEqualTo(5));
      });

      test('has only topics pub.dev accepts', () {
        expect(package.topics, everyElement(matches(topic)));
      });

      test('repeats no topic', () {
        expect(package.topics.toSet(), hasLength(package.topics.length));
      });

      test('points repository at its own folder', () {
        expect(
          package.field('repository'),
          '$repository/tree/main/packages/${package.name}',
        );
      });

      test('has the issue tracker', () {
        expect(package.field('issue_tracker'), '$repository/issues');
      });
    });
  }

  group('typed_graphql', () {
    final core = packages.firstWhere(
      (package) => package.name == 'typed_graphql',
    );

    test('names the platforms in its description', () {
      expect(
        core.field('description'),
        allOf(
          contains('Dart'),
          contains('VM'),
          contains('web'),
          contains('Wasm'),
        ),
      );
    });

    test('uses every topic slot', () {
      expect(core.topics, hasLength(5));
    });
  });
}
