# Agent Discoverability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare typed_graphql for discovery by AI coding agents before the
first release: pub.dev metadata, a README opening with a "Should I use
this?" block, `llms.txt`, `docs/discovery.md`, and offline tests that keep
all of it true.

**Architecture:** Metadata and documentation only; no library code changes.
A new workspace suite, `test/discovery/` (run by the root `dart test`), reads
the pubspecs with `package:yaml`, the READMEs through a small
`ReadmeOutline`, and `llms.txt` through `LlmsText`. The Markdown readers of
the core's documentation suite (`MarkdownFences`, `MarkdownLinks` in
`packages/typed_graphql/test/doc/`) are shared by import, not copied; the
link resolution moves into `MarkdownLinks.problemOf` so both suites use the
same checker.

**Tech Stack:** Dart 3.13 pub workspace, `package:test`, `package:yaml`
(new dev dependency of the never-published workspace root).

**Spec:** `docs/superpowers/specs/2026-10-14-agent-discoverability-design.md`
(approved; section 9 holds the owner's decisions). Read it with this plan.

## Global Constraints

- The rule for every sentence: **say only what works today** (spec §1). M3b
  is merged: schema validation and introspection work today; operation
  validation (M4) and execution (M5) do not.
- Approaches are compared, packages are not: no third-party package is named,
  ranked or judged in anything this plan writes (spec §4).
- Scope: `typed_graphql` gets the full treatment; `typed_graphql_server`,
  `_shelf`, `_client`, `_codegen`, `_builder` get only the `repository` fix,
  a CHANGELOG line and the "Not usable yet." line, and keep their
  descriptions (spec §9.1); `typed_graphql_conformance` (`publish_to: none`)
  is excluded everywhere.
- `description`: plain text, no markdown, 60 to 180 characters. `topics`: at
  most 5, each 2 to 32 characters of `a-z`, `0-9`, `-`, starting with a
  letter, ending alphanumeric, no consecutive hyphens.
- `repository`: `https://github.com/4akloon/graphql_dart/tree/main/packages/<name>`;
  `issue_tracker`: `https://github.com/4akloon/graphql_dart/issues`.
- `llms.txt` URLs: `https://github.com/4akloon/graphql_dart/blob/main/<path>`,
  absolute only.
- Recipes are not built (spec §9.3). No pub.dev package URLs before M16.
- `CLAUDE.md` binds the test code: test files at most 500 lines, nesting at
  most 3, no top-level function but `main`, no abbreviations, `@TestOn('vm')`
  on tests that use `dart:io`, `dart format` clean, `dart analyze
  --fatal-infos` clean.
- Each changed publishable package gets exactly one line in its existing
  `## 0.0.1 - Unreleased` CHANGELOG section (spec §8).
- Nothing is pushed, tagged or published. `dart pub publish` only with
  `--dry-run`.
- Memory safety on this machine: run every `dart test`, `dart analyze`,
  `dart format` and `dart doc` as
  `flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 <command> )'`,
  one at a time. The commands below are written bare for readability.

## Review Focus

1. A package README link that leaves the package folder (such as
   `../../docs/roadmap.md`) works on GitHub but 404s on pub.dev, which
   publishes the folder alone: the root links test must reject it (Task 4,
   "stays in the package").
2. An `llms.txt` link whose `#anchor` names a heading that was renamed, or
   whose path is a folder: the llms.txt test must fail, not only check that
   the path exists (Task 3, "is a file of the repository").
3. A skeleton package that leaves the skeleton state (M5 brings the server):
   `llms.txt` must not keep saying "skeleton" while the README banner says
   otherwise, and the "Not usable yet." line must follow the banner (Task 3,
   "gives the status ... as its README does"; Task 2, the skeleton test keys on
   the banner).
4. Files checked out with CRLF line endings: the root `dart test` runs on
   `windows-latest` in CI, so the README and `llms.txt` readers must read
   `\r\n` the same as `\n` (Task 2 and Task 3, "CRLF" tests).
5. A topic pub.dev rejects only at publish time (`GraphQL`, `graph_ql`,
   `a--b`, a repeated topic): the metadata test must catch it offline (Task 1,
   "has only topics pub.dev accepts", "repeats no topic").

## Claims of the README block and where they are shown

Every sentence Task 2 adds is shown by a guide section, the roadmap or a test.
Checked while writing this plan (a scratch program printed
`$.errors[0].message: expected a string` for a response whose first error has
a numeric message, and parsed a document with a comment and a block string
holding `{` without error).

| Sentence | Shown in |
|---|---|
| Parse, print and transform GraphQL queries and SDL in Dart | Language guide: "Parsing a document", "Printing", "Transforming" |
| build and validate a schema from SDL | Schema guide: "Building a schema from SDL", "Validating a schema" |
| read GraphQL responses as typed values | Wire protocol guide: "Responses" |
| every syntax error reported in one pass with its line and column | Language guide: "Parsing a document" ("one pass reports every error"); Diagnostics guide: "Reading a diagnostic" |
| runs on the VM, AOT and the web (dart2js and dart2wasm); "VM, web or Wasm" | Getting started guide, first paragraph; CI jobs `aot` and the Chrome runs |
| every problem as a value with a stable code and a place | Getting started guide: "Four rules"; Diagnostics guide: "Codes" |
| does not validate an operation or execute one: M4 and M5 | `docs/roadmap.md`, rows M4 and M5 |
| a document is a syntax tree (comments, block strings, nested selections) | Language guide: "The syntax tree", "Tokens" |
| `ResponsePayload.decode` checks a response and names the path of a wrong field | Wire protocol guide: "Errors" (`$.message: expected a string`), "Decode results" |
| the core depends only on `meta` | `packages/typed_graphql/pubspec.yaml`; `test/quality/layers_test.dart` |
| server, client and code generation packages are not usable yet | their README banners ("Status: skeleton.") |

## File map

| File | Task | Responsibility |
|---|---|---|
| `pubspec.yaml` (root) | 1 | `yaml` dev dependency for the workspace suite |
| `test/discovery/publishable_package.dart` | 1 | one package and its parsed pubspec |
| `test/discovery/workspace_packages.dart` | 1 | the publishable packages of `packages/` |
| `test/discovery/pubspec_metadata_test.dart` | 1 | description, topics, repository, issue tracker |
| `packages/*/pubspec.yaml` (six) | 1 | `repository`; the core's description and topics |
| `packages/*/CHANGELOG.md` (six) | 1, 2 | one line each |
| `.github/workflows/ci.yml` | 1 | the root test step's name |
| `test/discovery/readme_outline.dart` (+ `_test`) | 2 | opening paragraphs, status, sections of a README |
| `test/discovery/readme_test.dart` | 2 | the core's opening and block; skeleton line |
| `packages/typed_graphql/README.md` | 2 | opening sentence, "Should I use this?" |
| `packages/typed_graphql_{server,shelf,client,codegen,builder}/README.md` | 2 | "Not usable yet." line |
| `test/discovery/llms_entry.dart`, `llms_text.dart` (+ `_test`) | 3 | the llmstxt.org shape |
| `test/discovery/llms_file_test.dart` | 3 | the repository's `llms.txt` |
| `llms.txt` | 3 | the map for agents |
| `packages/typed_graphql/test/doc/markdown_links.dart` (+ `_test`) | 4 | `problemOf`, the shared resolution |
| `packages/typed_graphql/test/doc/doc_links_test.dart` | 4 | uses `problemOf` |
| `test/discovery/links_test.dart` | 4, 5 | root README, discovery page, package READMEs |
| `docs/discovery.md` | 5 | queries, rules, verification check, re-check procedure |
| `test/discovery/discovery_page_test.dart` | 5, 6 | the page and who links it |
| `CONTRIBUTING.md` | 5 | link to the page |
| `docs/roadmap.md` | 6 | the discoverability rule for plans |
| `CLAUDE.md`, `docs/README.md`, `docs/superpowers/HANDOFF.md` | 6 | where things are |

---

### Task 1: Workspace test support, metadata tests and the pubspec fixes

**Files:**
- Modify: `pubspec.yaml` (root)
- Create: `test/discovery/publishable_package.dart`
- Create: `test/discovery/workspace_packages.dart`
- Create: `test/discovery/pubspec_metadata_test.dart`
- Modify: `packages/typed_graphql/pubspec.yaml`, `packages/typed_graphql_server/pubspec.yaml`, `packages/typed_graphql_shelf/pubspec.yaml`, `packages/typed_graphql_client/pubspec.yaml`, `packages/typed_graphql_codegen/pubspec.yaml`, `packages/typed_graphql_builder/pubspec.yaml`
- Modify: the six `CHANGELOG.md` files of the same packages
- Modify: `.github/workflows/ci.yml:69`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `final class PublishablePackage(String name, YamlMap pubspec)` with
    `String? field(String key)` and `List<String> get topics`.
  - `final class WorkspacePackages` (const) with
    `List<PublishablePackage> publishable()`: packages in `packages/` without
    `publish_to: none`, in name order, read from the workspace root.

- [ ] **Step 1: Add the `yaml` dev dependency**

In the root `pubspec.yaml`, `dev_dependencies` becomes:

```yaml
dev_dependencies:
  lints: ^6.1.0
  test: ^1.31.0
  yaml: ^3.1.0
```

Run: `dart pub get` (repo root). Expected: resolves (`yaml` 3.1.x is already
in the lock as a transitive dependency of `test`).

- [ ] **Step 2: Write the support classes**

`test/discovery/publishable_package.dart`:

```dart
import 'package:yaml/yaml.dart';

/// A package of the workspace that pub.dev will show, read from its
/// `pubspec.yaml` the way pub reads it.
final class PublishablePackage(
  /// The folder of the package in `packages/`, which is also its name.
  final String name,

  /// The parsed pubspec.
  final YamlMap pubspec,
) {
  /// Creates a package.
  this;

  /// The text of the top-level [key], or null when it is absent or not
  /// text. A folded block (`>-`) is already joined into one line.
  String? field(String key) => switch (pubspec[key]) {
    final String text => text,
    _ => null,
  };

  /// The `topics` entries as written, empty when there are none.
  List<String> get topics => switch (pubspec['topics']) {
    final YamlList list => [for (final topic in list) '$topic'],
    _ => const [],
  };
}
```

`test/discovery/workspace_packages.dart`:

```dart
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'publishable_package.dart';

/// Reads the packages in `packages/` from the workspace root, where the
/// workspace suite runs.
final class WorkspacePackages {
  /// Creates the reader.
  const WorkspacePackages();

  /// Every package whose pubspec does not say `publish_to: none`, in name
  /// order.
  List<PublishablePackage> publishable() {
    final names = [
      for (final folder in Directory('packages').listSync())
        if (folder is Directory)
          folder.path.replaceAll(r'\', '/').split('/').last,
    ]..sort();
    return [
      for (final name in names)
        if (_pubspecOf(name) case final pubspec?
            when pubspec['publish_to'] != 'none')
          PublishablePackage(name, pubspec),
    ];
  }

  YamlMap? _pubspecOf(String name) {
    final file = File('packages/$name/pubspec.yaml');
    if (!file.existsSync()) return null;
    return switch (loadYaml(file.readAsStringSync())) {
      final YamlMap pubspec => pubspec,
      _ => throw FormatException('packages/$name/pubspec.yaml is not a map'),
    };
  }
}
```

- [ ] **Step 3: Write the failing metadata test**

`test/discovery/pubspec_metadata_test.dart`:

```dart
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
```

- [ ] **Step 4: Run it to see it fail**

Run: `dart test test/discovery/pubspec_metadata_test.dart` (repo root).
Expected: 8 failures: "points repository at its own folder" for all six
packages (`Actual: 'https://github.com/4akloon/graphql_dart'`), and the two
`typed_graphql` group tests (the current description has no "VM"; the topics
are `['graphql']`).

- [ ] **Step 5: Fix the pubspecs**

In each of the six publishable pubspecs, replace

```yaml
repository: https://github.com/4akloon/graphql_dart
```

with the package's own folder, for example in `packages/typed_graphql_shelf/pubspec.yaml`:

```yaml
repository: https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql_shelf
```

(`typed_graphql`, `typed_graphql_server`, `typed_graphql_shelf`,
`typed_graphql_client`, `typed_graphql_codegen`, `typed_graphql_builder`:
each ends in its own name.) Leave `typed_graphql_conformance` alone.

In `packages/typed_graphql/pubspec.yaml` also replace the description and the
topics (the description is 152 characters):

```yaml
description: >-
  Parses, prints and builds GraphQL documents and schemas in pure Dart for the VM, web and Wasm, with error-resilient diagnostics and wire-protocol types.
```

```yaml
topics: [graphql, parser, ast, sdl, schema]
```

- [ ] **Step 6: Add the CHANGELOG lines**

`packages/typed_graphql/CHANGELOG.md`: append at the end of the
`## 0.0.1 - Unreleased` section (the end of the file):

```markdown
- pub.dev metadata: a description that says what the package does today, the
  topics `graphql`, `parser`, `ast`, `sdl` and `schema`, and a `repository`
  URL that points at the package folder, so pub.dev resolves the README's
  relative links.
```

In each of the five skeleton CHANGELOGs (`typed_graphql_server`, `_shelf`,
`_client`, `_codegen`, `_builder`), after `- Package skeleton.`, add:

```markdown
- `repository` points at the package folder, so pub.dev resolves the README's
  relative links.
```

- [ ] **Step 7: Rename the CI step**

In `.github/workflows/ci.yml`, the step that runs the root `dart test`:

```yaml
      - name: Test the code rules and the discovery checks (workspace root)
        run: dart test
```

- [ ] **Step 8: Run the tests to see them pass**

Run: `dart pub get && dart test test/discovery/pubspec_metadata_test.dart`
Expected: `All tests passed!` (45 tests).

Run: `dart format --output=none --set-exit-if-changed packages test` and
`dart analyze --fatal-infos` (repo root). Expected: 0 changed, "No issues
found!".

Run: `dart test` (repo root). Expected: `All tests passed!` (the code rules
now also measure `test/discovery/`).

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml test/discovery .github/workflows/ci.yml packages/*/pubspec.yaml packages/*/CHANGELOG.md
git commit -m "feat(workspace): check the pub.dev metadata and point repository at each package

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The core README opening, "Should I use this?", and the skeleton line

**Files:**
- Create: `test/discovery/readme_outline.dart`
- Create: `test/discovery/readme_outline_test.dart`
- Create: `test/discovery/readme_test.dart`
- Modify: `packages/typed_graphql/README.md`
- Modify: `packages/typed_graphql_{server,shelf,client,codegen,builder}/README.md`
- Modify: the six publishable `CHANGELOG.md` files (the Task 1 lines)

**Interfaces:**
- Consumes: `WorkspacePackages().publishable()` and `PublishablePackage.name`
  (Task 1); `MarkdownFences().proseLines(String markdown)` from
  `packages/typed_graphql/test/doc/markdown_fence.dart` (exists since M3c).
- Produces: `final class ReadmeOutline(String markdown)` with
  `List<String> get headings` (the `##` headings), `List<String> get opening`
  (paragraphs between the title and the first `##`, badges left out, lines
  joined with a space), `String? get status` (the word of
  `> **Status: <word>.**`), `String section(String heading)` (text under a
  `##` heading, `''` when absent).

The existing test `packages/typed_graphql/test/doc/example_test.dart`
requires the README's first `dart` fence to equal `example/example.dart`: the
new block has no code fence, so it keeps passing; do not add one.

- [ ] **Step 1: Write the outline and its failing test**

`test/discovery/readme_outline.dart`:

```dart
// The core's documentation suite owns the Markdown readers; the workspace
// suite shares them instead of keeping a copy that could drift.
import '../../packages/typed_graphql/test/doc/markdown_fence.dart';

/// The parts of a README that an agent reads first: the paragraphs before
/// the first section, and the `##` sections. Fenced code is left out, so a
/// `#` comment in a fence is not a heading.
final class ReadmeOutline(String markdown) {
  /// Creates the outline of [markdown].
  this;

  final List<String> _lines = const MarkdownFences().proseLines(markdown);

  static final RegExp _section = RegExp(r'^##\s+(.*?)\s*$');
  static final RegExp _status = RegExp(r'^> \*\*Status: ([^.*]+)\.\*\*');

  /// The `##` headings, in order.
  List<String> get headings => [
    for (final line in _lines)
      if (_section.firstMatch(line) case final match?) match[1]!,
  ];

  /// The paragraphs between the `#` title and the first `##` heading,
  /// badge lines left out; the lines of a paragraph are joined with a
  /// space.
  List<String> get opening {
    final firstSection = _lines.indexWhere(_section.hasMatch);
    return _paragraphs(
      _lines.sublist(1, firstSection < 0 ? _lines.length : firstSection),
    ).where((paragraph) => !paragraph.startsWith(RegExp(r'\[?!\['))).toList();
  }

  /// What the status banner (`> **Status: skeleton.**`) says, such as
  /// `skeleton`, or null when the opening has no banner.
  String? get status =>
      opening.map(_status.firstMatch).nonNulls.firstOrNull?[1];

  /// The text under the `##` heading [heading] up to the next `##`
  /// heading, its lines joined with `\n`; empty when there is no such
  /// heading.
  String section(String heading) {
    final start = _lines.indexWhere(
      (line) => _section.firstMatch(line)?[1] == heading,
    );
    if (start < 0) return '';
    final rest = _lines.sublist(start + 1);
    final end = rest.indexWhere(_section.hasMatch);
    return rest.sublist(0, end < 0 ? rest.length : end).join('\n').trim();
  }

  List<String> _paragraphs(List<String> lines) {
    final paragraphs = <String>[];
    final current = <String>[];
    for (final line in [...lines, '']) {
      if (line.trim().isNotEmpty) {
        current.add(line.trim());
      } else if (current.isNotEmpty) {
        paragraphs.add(current.join(' '));
        current.clear();
      }
    }
    return paragraphs;
  }
}
```

`test/discovery/readme_outline_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'readme_outline.dart';

void main() {
  const readme =
      '# name\n'
      '\n'
      '![Dart](https://img.shields.io/a)\n'
      '[![CI](https://x.dev/b.svg)](https://x.dev/c)\n'
      '\n'
      '**Parse GraphQL\n'
      'in Dart.** More.\n'
      '\n'
      '> **Status: skeleton.** Later.\n'
      '\n'
      '## Install\n'
      '\n'
      '```sh\n'
      '## not a heading\n'
      '```\n'
      '\n'
      '## Usage\n'
      '\n'
      'Text.\n';

  test('the opening paragraphs leave out the title and the badges', () {
    expect(ReadmeOutline(readme).opening, [
      '**Parse GraphQL in Dart.** More.',
      '> **Status: skeleton.** Later.',
    ]);
  });

  test('reads the status from the banner', () {
    expect(ReadmeOutline(readme).status, 'skeleton');
  });

  test('a README without a banner has no status', () {
    expect(ReadmeOutline('# name\n\nText.\n').status, isNull);
  });

  test('a fenced line that looks like a heading is not one', () {
    expect(ReadmeOutline(readme).headings, ['Install', 'Usage']);
  });

  test('a section runs up to the next heading', () {
    expect(ReadmeOutline(readme).section('Usage'), 'Text.');
  });

  test('a missing section is empty', () {
    expect(ReadmeOutline(readme).section('License'), isEmpty);
  });

  test('reads a README written with CRLF line endings', () {
    final windows = ReadmeOutline(readme.replaceAll('\n', '\r\n'));
    expect(windows.headings, ['Install', 'Usage']);
  });
}
```

Write the test file first and run
`dart test test/discovery/readme_outline_test.dart`: it fails to load
(`ReadmeOutline` is not defined); then add `readme_outline.dart` and run it
again. Expected: `All tests passed!` (7 tests).

- [ ] **Step 2: Write the failing README test**

`test/discovery/readme_test.dart`:

```dart
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

  // A skeleton exports nothing: an agent that lands on it must not try it.
  for (final package in const WorkspacePackages().publishable()) {
    final path = 'packages/${package.name}/README.md';
    final outline = ReadmeOutline(File(path).readAsStringSync());
    if (outline.status != 'skeleton') continue;
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
```

- [ ] **Step 3: Run it to see it fail**

Run: `dart test test/discovery/readme_test.dart`
Expected: 11 failures: "opens with the task in the words of the first query"
(the opening starts with `**GraphQL for Dart`), "has "Should I use this?"
right after Install" (`Actual: <-1>`), the four label tests (`Actual: ''`),
and the five skeleton tests (the paragraph after the banner starts with
`Planned`).

- [ ] **Step 4: Rewrite the core README opening and add the block**

In `packages/typed_graphql/README.md`, replace the opening paragraph

```markdown
**GraphQL for Dart, written from scratch and fully typed: the language, the
type system, validation and the wire protocol, with diagnostics instead of
exceptions.** Pure Dart, depends only on `meta`, runs on the VM, AOT and the
web (dart2js and dart2wasm). Part of
[typed_graphql](https://github.com/4akloon/graphql_dart).
```

with

```markdown
**Parse, print and transform GraphQL queries and SDL in Dart, build and
validate a schema from SDL, and read GraphQL responses as typed values, with
every syntax error reported in one pass with its line and column.** Pure
Dart, depends only on `meta`, runs on the VM, AOT and the web (dart2js and
dart2wasm). Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
```

The status banner stays directly under it, unchanged.

In `## Contents`, after `- [Install](#install)`, add:

```markdown
- [Should I use this?](#should-i-use-this)
```

Between the Install section (after its closing yaml fence) and
`## A quick tour`, insert:

```markdown
## Should I use this?

- **Use it when** you need to parse, print, rewrite or inspect GraphQL text,
  or build and validate a schema from SDL, in Dart (VM, web or Wasm), and want
  every problem as a value with a stable code and a place
  ([Language](doc/language.md#parsing-a-document),
  [Schema](doc/schema.md#building-a-schema-from-sdl),
  [Diagnostics](doc/diagnostics.md#reading-a-diagnostic)).
- **You do not need it when** you only send a query string to a server and
  read the JSON back. Today it also does not validate an operation against a
  schema or execute one: those arrive in stages M4 and M5.
- **What it replaces**: matching GraphQL text with regular expressions or
  string splitting, and reading responses as `Map<String, dynamic>`. A regular
  expression does not see comments, block strings or nested selections, and
  fails silently on them; a dynamic map reads `errors` and `path` without
  checking their shape, so a wrong field is a runtime cast error far from its
  cause. Here a document is a syntax tree, and `ResponsePayload.decode` checks
  a response and names the path of a wrong field
  ([Wire protocol](doc/protocol.md#responses)).
- **Which package**: this one, the core, which depends only on `meta`. The
  server, client and code generation packages build on it and are not usable
  yet.

```

Before writing, re-read the guide sections in the "Claims" table of this
plan; if a guide no longer shows a sentence, change the sentence, not the
test.

- [ ] **Step 5: Add the skeleton line**

In each of `packages/typed_graphql_server/README.md`,
`packages/typed_graphql_shelf/README.md`,
`packages/typed_graphql_client/README.md`,
`packages/typed_graphql_codegen/README.md` and
`packages/typed_graphql_builder/README.md`, the status blockquote ends with
`nothing is exported yet.`; after it and its blank line, before the
`Planned` paragraph, insert this paragraph (one line) and a blank line:

```markdown
**Not usable yet.** This package exports nothing; the part of typed_graphql that works today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql).
```

The link is absolute: pub.dev publishes the package folder alone (Task 4
checks this).

- [ ] **Step 6: Merge the CHANGELOG lines**

In `packages/typed_graphql/CHANGELOG.md`, replace the line Task 1 added with:

```markdown
- pub.dev metadata and README: a description and an opening sentence that say
  what the package does today, a "Should I use this?" section after Install,
  the topics `graphql`, `parser`, `ast`, `sdl` and `schema`, and a
  `repository` URL that points at the package folder, so pub.dev resolves the
  README's relative links.
```

In each of the five skeleton CHANGELOGs, replace the Task 1 line with:

```markdown
- `repository` points at the package folder, so pub.dev resolves the README's
  relative links; the README says the package is not usable yet.
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `dart test test/discovery` (repo root). Expected: `All tests passed!`.

Run, in `packages/typed_graphql`:
`dart test test/doc/doc_links_test.dart test/doc/example_test.dart`.
Expected: `All tests passed!` (the new anchors resolve; the README's first
program is still `example/example.dart`).

Run: `dart format --output=none --set-exit-if-changed packages test`,
`dart analyze --fatal-infos`. Expected: clean.

- [ ] **Step 8: Commit**

```bash
git add test/discovery packages/*/README.md packages/*/CHANGELOG.md
git commit -m "docs(typed_graphql): open the README with the task and answer \"Should I use this?\"

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `llms.txt`

**Files:**
- Create: `test/discovery/llms_entry.dart`
- Create: `test/discovery/llms_text.dart`
- Create: `test/discovery/llms_text_test.dart`
- Create: `test/discovery/llms_file_test.dart`
- Create: `llms.txt`

**Interfaces:**
- Consumes: `WorkspacePackages().publishable()` (Task 1);
  `ReadmeOutline(markdown).status` (Task 2); from
  `packages/typed_graphql/test/doc/markdown_links.dart`:
  `MarkdownLinks().relativeIn(String) → List<MarkdownLink>` and
  `MarkdownLinks().anchorsIn(String) → Set<String>` (both exist since M3c).
- Produces: `final class LlmsEntry(String title, String url, String description)`;
  `final class LlmsText(String text)` with `List<String> get titles`,
  `List<String> get summaries`, `List<String> get sections`,
  `List<LlmsEntry> entriesOf(String heading)`.

- [ ] **Step 1: Write the reader's failing test**

`test/discovery/llms_text_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'llms_text.dart';

void main() {
  const text =
      '# name\n'
      '\n'
      '> One line\n'
      '> and two.\n'
      '\n'
      '## Docs\n'
      '\n'
      '- [A](https://x.dev/a.md): the a\n'
      '- [B](https://x.dev/b.md)\n'
      '\n'
      '## More\n'
      '\n'
      '- [C](https://x.dev/c.md): the c\n';

  test('reads the title', () {
    expect(LlmsText(text).titles, ['name']);
  });

  test('joins the lines of a summary', () {
    expect(LlmsText(text).summaries, ['One line and two.']);
  });

  test('reads the sections in order', () {
    expect(LlmsText(text).sections, ['Docs', 'More']);
  });

  test('reads the entries of one section only', () {
    final entries = LlmsText(text).entriesOf('Docs');
    expect(entries.map((entry) => entry.url), [
      'https://x.dev/a.md',
      'https://x.dev/b.md',
    ]);
  });

  test('an entry without a colon has an empty description', () {
    expect(LlmsText(text).entriesOf('Docs').last.description, isEmpty);
  });

  test('a missing section has no entries', () {
    expect(LlmsText(text).entriesOf('Optional'), isEmpty);
  });

  test('reads a file written with CRLF line endings', () {
    final windows = LlmsText(text.replaceAll('\n', '\r\n'));
    expect(windows.entriesOf('More').single.description, 'the c');
  });
}
```

Run: `dart test test/discovery/llms_text_test.dart`. Expected: fails to load
(`llms_text.dart` does not exist).

- [ ] **Step 2: Write the reader**

`test/discovery/llms_entry.dart`:

```dart
/// One link of an `llms.txt` section, written `- [title](url): description`.
final class LlmsEntry(
  /// The link text.
  final String title,

  /// The link target.
  final String url,

  /// The text after the colon; empty when the line has none.
  final String description,
) {
  /// Creates an entry.
  this;
}
```

`test/discovery/llms_text.dart`:

```dart
import 'llms_entry.dart';

/// An `llms.txt` file in the llmstxt.org shape: a `#` title, a `>`
/// summary, then `##` sections whose lines are links with a description.
final class LlmsText(String text) {
  /// Reads [text].
  this;

  final List<String> _lines = text.replaceAll('\r\n', '\n').split('\n');

  static final RegExp _entry = RegExp(
    r'^- \[([^\]]+)\]\((\S+)\)(?::\s*(.*))?$',
  );

  /// The `#` headings, in order.
  List<String> get titles => [
    for (final line in _lines)
      if (line.startsWith('# ')) line.substring(2).trim(),
  ];

  /// The blockquotes: each run of `>` lines, joined with a space.
  List<String> get summaries {
    final summaries = <String>[];
    final current = <String>[];
    for (final line in [..._lines, '']) {
      if (line.startsWith('>')) {
        current.add(line.substring(1).trim());
      } else if (current.isNotEmpty) {
        summaries.add(current.join(' '));
        current.clear();
      }
    }
    return summaries;
  }

  /// The `##` headings, in order.
  List<String> get sections => [
    for (final line in _lines)
      if (line.startsWith('## ')) line.substring(3).trim(),
  ];

  /// The link lines of the section [heading], in order; empty when there
  /// is no such section.
  List<LlmsEntry> entriesOf(String heading) {
    final start = _lines.indexOf('## $heading');
    if (start < 0) return const [];
    return [
      for (final line in _lines.skip(start + 1).takeWhile(_isInSection))
        if (_entry.firstMatch(line) case final match?)
          LlmsEntry(match[1]!, match[2]!, match[3] ?? ''),
    ];
  }

  bool _isInSection(String line) => !line.startsWith('## ');
}
```

Run: `dart test test/discovery/llms_text_test.dart`. Expected:
`All tests passed!` (7 tests).

- [ ] **Step 3: Write the failing test of the repository's `llms.txt`**

`test/discovery/llms_file_test.dart`:

```dart
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
      unorderedEquals(guides),
    );
  });
}
```

Run: `dart test test/discovery/llms_file_test.dart`. Expected: fails to load
with `PathNotFoundException` for `llms.txt`.

- [ ] **Step 4: Write `llms.txt`**

`llms.txt` at the repository root (the summary is one line; the packages are
in name order, as `publishable()` lists them):

```markdown
# typed_graphql

> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code and a place or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. Operation validation (stage M4), execution (M5) and the server, client and code generation packages are not built yet, and nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.

## Packages

- [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, wire protocol and diagnostics
- [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
- [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): skeleton; client runtime and normalized cache, not usable yet (M11, M12)
- [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): skeleton; code generator and its CLI, not usable yet (M8, M10)
- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): skeleton; typed schema builder, executor and transport handlers, not usable yet (M5 to M7)
- [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)

## Guides

- [Getting started](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/getting_started.md): the layers, the four rules, a first program
- [Language](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/language.md): parse, print, visit and rewrite documents; schema coordinates; tokens
- [Diagnostics](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/diagnostics.md): sources, spans, codes and the sink
- [Wire protocol](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/protocol.md): JsonValue, requests, responses and errors
- [Schema](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/schema.md): build a schema from SDL, read, validate, extend and print it; resolve coordinates
- [Scalars and codecs](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/scalars.md): the built-in scalar codecs and your own
- [Introspection](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/introspection.md): the introspection query, a schema's answer, and a schema built from an answer

## Reference

- [Roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md): the stages M1 to M16 and what each delivers
- [Requirements](https://github.com/4akloon/graphql_dart/blob/main/docs/requirements.md): the requirements R0 to R11
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `dart test test/discovery` (repo root). Expected: `All tests passed!`.
Run: `dart format --output=none --set-exit-if-changed packages test`,
`dart analyze --fatal-infos`, `dart test` (root). Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add llms.txt test/discovery
git commit -m "docs: add llms.txt and check its shape and links

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: One link checker for the guides, the root README and every package README

**Files:**
- Modify: `packages/typed_graphql/test/doc/markdown_links.dart` (add `problemOf` after `relativeIn`)
- Modify: `packages/typed_graphql/test/doc/markdown_links_test.dart`
- Modify: `packages/typed_graphql/test/doc/doc_links_test.dart`
- Create: `test/discovery/links_test.dart`

**Interfaces:**
- Consumes: `WorkspacePackages().publishable()` (Task 1);
  `MarkdownLinks.relativeIn`, `anchorsIn`, `readTarget`, `MarkdownLink(line, target)`.
- Produces: `String? MarkdownLinks.problemOf(String from, String target)`:
  null when `target`, written in the file at `from` (both relative to the
  folder the test runs in), leads to an existing file or folder and, with an
  anchor, to a heading of that file; otherwise
  `'<path> does not exist'` or `'<path> has no heading with the anchor #<anchor>'`.
  A folder with an anchor still throws `readTarget`'s `FormatException`.

- [ ] **Step 1: Write the failing tests of `problemOf`**

In `packages/typed_graphql/test/doc/markdown_links_test.dart`, before the
test `'a link to a directory with an anchor fails with a clear message'`,
insert (the package suite runs in `packages/typed_graphql`):

```dart
  test('a link to an existing file and heading has no problem', () {
    expect(links.problemOf('doc/language.md', '../README.md#install'), isNull);
  });

  test('a link to a folder has no problem', () {
    expect(links.problemOf('README.md', 'doc'), isNull);
  });

  test('a link to a missing file says the file does not exist', () {
    expect(
      links.problemOf('README.md', 'doc/missing.md'),
      'doc/missing.md does not exist',
    );
  });

  test('a link to a missing heading names the anchor', () {
    expect(
      links.problemOf('README.md', '#missing'),
      'README.md has no heading with the anchor #missing',
    );
  });

```

Run, in `packages/typed_graphql`: `dart test test/doc/markdown_links_test.dart`.
Expected: fails to compile (`The method 'problemOf' isn't defined`).

- [ ] **Step 2: Move the resolution into `MarkdownLinks`**

In `packages/typed_graphql/test/doc/markdown_links.dart`, after `relativeIn`
and before `readTarget`, add:

```dart
  /// Why the link [target], written in the file at [from], leads nowhere,
  /// or null when it leads to a file or folder and, with an anchor, to a
  /// heading of that file. Both paths are from the folder the tests run in.
  String? problemOf(String from, String target) {
    final uri = Uri.parse(from).resolve(target);
    if (FileSystemEntity.typeSync(uri.path) == .notFound) {
      return '${uri.path} does not exist';
    }
    if (uri.fragment.isEmpty) return null;
    final anchors = anchorsIn(readTarget(uri.path));
    if (anchors.contains(uri.fragment)) return null;
    return '${uri.path} has no heading with the anchor #${uri.fragment}';
  }
```

In `packages/typed_graphql/test/doc/doc_links_test.dart`, remove
`import 'dart:io';` and replace the body of the `'$path:$line -> $target'`
test:

```dart
        test('$path:$line -> $target', () {
          expect(links.problemOf(path, target), isNull);
        });
```

Run, in `packages/typed_graphql`:
`dart test test/doc/markdown_links_test.dart test/doc/doc_links_test.dart`.
Expected: `All tests passed!`.

- [ ] **Step 3: Write the workspace links test**

`test/discovery/links_test.dart`:

```dart
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
  final pages = ['README.md', ...readmes];

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
```

The import reaches into the core's `test/doc/`: the workspace root is never
published, so the shared checker stays where the core suite needs it and no
copy exists.

- [ ] **Step 4: Run the tests to see them pass**

Run: `dart test test/discovery/links_test.dart` (repo root). Expected:
`All tests passed!` (79 tests: every relative link of the root README and the
seven package READMEs, then the publishable READMEs' in-package checks).

To see the in-package check bite, temporarily add `[roadmap](../../docs/roadmap.md)`
to `packages/typed_graphql_shelf/README.md`, run the test (expected: one
failure, "stays in the package"), and revert.

Run: `dart format --output=none --set-exit-if-changed packages test`,
`dart analyze --fatal-infos`, `dart test` (root). Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add packages/typed_graphql/test/doc test/discovery/links_test.dart
git commit -m "test(workspace): check the links of every README with the shared checker

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `docs/discovery.md`

**Files:**
- Create: `docs/discovery.md`
- Create: `test/discovery/discovery_page_test.dart`
- Modify: `test/discovery/links_test.dart` (the `pages` list)
- Modify: `CONTRIBUTING.md` ("Repository layout")

**Interfaces:**
- Consumes: `ReadmeOutline(markdown).headings`, `.section(heading)` (Task 2);
  `MarkdownLinks.relativeIn`, `problemOf` (Task 4).
- Produces: `docs/discovery.md` with the `##` sections "Say only what works
  today", "Queries" (a table `| Query | Stage | Works today |`), "Metadata"
  (with `### Repository verification`), "README", "llms.txt", "Links", "After
  a release". Task 6 links it from the roadmap.

- [ ] **Step 1: Write the failing test**

`test/discovery/discovery_page_test.dart`:

```dart
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

  test('CONTRIBUTING.md links to it', () {
    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    expect(
      linkedFrom('CONTRIBUTING.md', contributing),
      contains('docs/discovery.md'),
    );
  });
}
```

In `test/discovery/links_test.dart`, the page list becomes:

```dart
  final pages = ['README.md', 'docs/discovery.md', ...readmes];
```

Run: `dart test test/discovery/discovery_page_test.dart test/discovery/links_test.dart`.
Expected: both fail to load with `PathNotFoundException` for
`docs/discovery.md`.

- [ ] **Step 2: Look up repository verification (open check, spec §3)**

Fetch https://pub.dev/help, https://pub.dev/help/publishing,
https://pub.dev/help/scoring, https://pub.dev/help/search and
https://dart.dev/tools/pub/pubspec, and look for what pub.dev checks before it
treats a `repository` as verified (and rewrites relative README links). Do not
guess. While this plan was written (2026-10-14), none of these pages described
it: the pubspec reference says only that `repository` "should contain the URL
for your package's source code repository", and the search help lists the
name, description, README and doc comments as what search reads. If the pages
now say more, replace the "Repository verification" paragraph below with a
short quote and its link, and keep the date of the check.

- [ ] **Step 3: Write the page**

`docs/discovery.md`:

```markdown
# Discovery

How an AI coding agent in a project that does not use typed_graphql finds it
through pub.dev and web search, chooses it over a hand-written solution, and
sees what to copy. This page is for maintainers; the design is the
[agent discoverability spec](superpowers/specs/2026-10-14-agent-discoverability-design.md).
The workspace suite in `test/discovery/` checks what can be checked offline.

## Say only what works today

The rule for every sentence of a README, a pubspec description and
`llms.txt`: **say only what works today.** An agent that follows a README to
a feature that does not exist is worse off than one that finds nothing. Name
what is missing and the stage that brings it. Compare approaches, never
packages: no third-party package is named, ranked or judged.

## Queries

The searches typed_graphql answers, or will. A stage that makes a query true
adds its row (or turns it to "yes") together with its README line and its
`llms.txt` entry; until then the query is not targeted anywhere.

| Query | Stage | Works today |
|---|---|---|
| parse GraphQL query dart | M2 | yes |
| print or format a GraphQL document dart | M2 | yes |
| GraphQL syntax error line column dart | M2 | yes |
| GraphQL AST visitor transform dart | M2 | yes |
| build GraphQL schema from SDL dart | M3 | yes |
| print GraphQL schema SDL dart | M3 | yes |
| decode GraphQL response errors dart | M1 | yes |
| GraphQL request response JSON types dart | M1 | yes |
| validate a GraphQL schema dart | M3 | yes |
| GraphQL introspection query schema dart | M3 | yes |
| validate a GraphQL operation dart | M4 | no |
| execute a GraphQL query dart | M5 | no |
| GraphQL server dart | M7 | no |
| generate a typed GraphQL client dart | M10 | no |

## Metadata

pub.dev searches a package's name, description, README and doc comments
([pub.dev search help](https://pub.dev/help/search)). The pubspec rules, from
the [pubspec reference](https://dart.dev/tools/pub/pubspec):

- `description`: plain text, no markdown or HTML, 60 to 180 characters. Start
  with a verb and the platform.
- `topics`: at most 5; each 2 to 32 characters of `a-z`, `0-9` and `-`,
  starting with a letter, ending with a letter or digit, no `--`.
- `repository`: the package folder, so that pub.dev can rewrite the README's
  relative links and images:
  `https://github.com/4akloon/graphql_dart/tree/main/packages/<name>` (the
  form the pub-dev maintainers give in
  [dart-lang/pub-dev#5068](https://github.com/dart-lang/pub-dev/issues/5068)).
- `issue_tracker`: `https://github.com/4akloon/graphql_dart/issues`.
- Images and badges use absolute URLs; doc comments use no relative link,
  because the API reference does not rewrite them.

### Repository verification

pub.dev rewrites relative links only for a verified repository. What it
checks to verify one is an open question. Checked on 2026-10-14:
[pub.dev help](https://pub.dev/help), its
[publishing](https://pub.dev/help/publishing),
[scoring](https://pub.dev/help/scoring) and
[search](https://pub.dev/help/search) pages, and the
[pubspec reference](https://dart.dev/tools/pub/pubspec), which says only that
`repository` "should contain the URL for your package's source code
repository". None of them describes the verification. Look again before the
release (M16) and replace this paragraph with what pub.dev says, quoted and
linked.

## README

- The core's README opens with the task in the words of the queries, then
  the status banner. Right after Install comes **Should I use this?** with
  four labels: *Use it when*, *You do not need it when*, *What it replaces*,
  *Which package*. Every claim there is shown in a guide, and the item links
  the guide section.
- A skeleton package says **Not usable yet.** right under its status banner
  and makes no other claim.
- A link that leaves the package folder is an absolute URL: pub.dev publishes
  the folder alone.

## llms.txt

`llms.txt` at the repository root has the [llmstxt.org](https://llmstxt.org)
shape: one `#` title, one `>` summary, then the sections *Packages* (each with
its README status), *Guides* (every `packages/typed_graphql/doc/*.md`) and
*Reference*. Every link is an absolute
`https://github.com/4akloon/graphql_dart/blob/main/<path>` URL to a file of
the repository. pub.dev package URLs are added at M16.

## Links

Every relative link of the root README, this page and every package README
leads to a file or folder, and an anchor to a heading; the checker is the
core documentation suite's `MarkdownLinks`.

## After a release

At M16, and after each later release, once the owner has said yes to
publishing:

1. Search pub.dev and the web for every query marked "yes".
2. Write what came up, query by query, into the release pull request's
   description.
3. Fix a README, description or `llms.txt` sentence that a result shows to
   be wrong or missing, in a follow-up change.

No document promises a ranking.
```

(If Step 2 found the verification steps, the "Repository verification"
paragraph holds them instead.)

- [ ] **Step 4: Link it from CONTRIBUTING.md**

In `CONTRIBUTING.md`, "Repository layout", after the line
`[CLAUDE.md](CLAUDE.md) is the full guide to the code and its rules.`, add:

```markdown
[docs/discovery.md](docs/discovery.md) says how agents and people find the
packages, and what a README, a pubspec description and `llms.txt` may claim.
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `dart test test/discovery` (repo root). Expected: `All tests passed!`.
Run: `dart format --output=none --set-exit-if-changed packages test`,
`dart analyze --fatal-infos`, `dart test` (root). Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add docs/discovery.md CONTRIBUTING.md test/discovery
git commit -m "docs: add the discovery page with the queries and the rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The roadmap rule, CLAUDE.md, docs/README.md and HANDOFF

**Files:**
- Modify: `test/discovery/discovery_page_test.dart`
- Modify: `docs/roadmap.md` ("Rules for plans", at the end of the file)
- Modify: `CLAUDE.md` ("Documents", "Commands", "Documentation", "Where things are")
- Modify: `docs/README.md` (the table)
- Modify: `docs/superpowers/HANDOFF.md` ("State", "Open for publishing (M16)")

**Interfaces:**
- Consumes: `linkedFrom` and `ReadmeOutline.section` in
  `discovery_page_test.dart` (Task 5).
- Produces: the roadmap rule of spec §9.2.

- [ ] **Step 1: Write the failing test**

In `test/discovery/discovery_page_test.dart`, before
`test('CONTRIBUTING.md links to it', ...)`, add:

```dart
  test("the roadmap's rules for plans link to it", () {
    final rules = ReadmeOutline(roadmap).section('Rules for plans');
    expect(linkedFrom('docs/roadmap.md', rules), contains('docs/discovery.md'));
  });

```

Run: `dart test test/discovery/discovery_page_test.dart`. Expected: one
failure, `Expected: contains 'docs/discovery.md'`, `Actual: []`.

- [ ] **Step 2: Add the roadmap rule**

Append to `docs/roadmap.md` (the last list item of "Rules for plans"):

```markdown
- Discoverability ships with the stage too: a stage that adds a capability adds
  its search query to [discovery.md](discovery.md), its line in the core's
  README and its `llms.txt` entry, and every sentence says only what works
  when the stage ends. The plan's self-review checks that task exists.
```

Run: `dart test test/discovery` (repo root). Expected: `All tests passed!`.

- [ ] **Step 3: Update CLAUDE.md**

In "Documents", after the `docs/research/` item, add:

```markdown
- `docs/discovery.md` - how agents find the packages: the search queries and
  the stage that unlocks each, the pubspec metadata rules, what a README and
  `llms.txt` may claim (only what works today), the re-check after a release.
  `llms.txt` at the root is the map for agents.
```

In "Commands", the root test line becomes:

```text
dart test                                                     # repo root: the code rules and the discovery checks
```

In "Documentation", after the sentence ending `adds its section to the guide
of its layer in the same commit.`, add:

```markdown
A stage that adds a capability adds its query to `docs/discovery.md`, its
line in the core's README and its `llms.txt` entry; a README, a pubspec
description and `llms.txt` say only what works today. A link in a package
README that leaves the package folder is an absolute URL.
```

In "Where things are", after the "Code rules suite" item, add:

```markdown
- Discovery suite: `test/discovery/` at the workspace root (pubspec
  metadata, README openings, `llms.txt`, links); it imports the core's
  `MarkdownFences` and `MarkdownLinks` from
  `packages/typed_graphql/test/doc/` instead of copying them.
```

- [ ] **Step 4: Update docs/README.md**

In the table, after the `roadmap.md` row, add:

```markdown
| `discovery.md` | How agents find the packages: queries, metadata, README and `llms.txt` rules |
```

- [ ] **Step 5: Update HANDOFF.md**

In the "State" table, after the "M3c Core docs" row, add:

```markdown
| Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | implemented on its branch (not merged): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
```

In "Open for publishing (M16)", replace the first item (the one that begins
`- pub.dev rewrites relative README links only when`) with:

```markdown
- Every publishable pubspec's `repository` points at its package folder
  (`https://github.com/4akloon/graphql_dart/tree/main/packages/<pkg>`), so
  pub.dev can rewrite relative README links once the repository is verified.
  What pub.dev checks for verification is still open: confirm it before
  publishing ([discovery.md](../discovery.md), "Repository verification").
- After publishing, search pub.dev and the web for each query and record the
  results in the release PR ([discovery.md](../discovery.md), "After a
  release").
```

- [ ] **Step 6: Run the checks**

Run: `dart test test/discovery` (root), and in `packages/typed_graphql`:
`dart test test/doc/doc_links_test.dart`. Expected: `All tests passed!`.

- [ ] **Step 7: Commit**

```bash
git add test/discovery docs/roadmap.md CLAUDE.md docs/README.md docs/superpowers/HANDOFF.md
git commit -m "docs: add the discoverability rule to the roadmap and the guides for contributors

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Whole-branch verification

**Files:** none, unless a check fails (then fix in the task's files and
commit with a `fix(...)` message).

**Interfaces:**
- Consumes: everything above.
- Produces: the evidence for the final review.

- [ ] **Step 1: Format and analyze**

Run (repo root): `dart format --output=none --set-exit-if-changed packages test`
Expected: `Formatted ... files (0 changed)`.

Run: `dart analyze --fatal-infos`. Expected: `No issues found!`.

- [ ] **Step 2: The workspace suite**

Run (repo root): `dart test`. Expected: `All tests passed!` (the code rules
and about 230 discovery tests).

- [ ] **Step 3: Every package suite**

Run each, one at a time:

```sh
cd packages/typed_graphql && dart test
cd packages/typed_graphql_server && dart test
cd packages/typed_graphql_shelf && dart test
cd packages/typed_graphql_client && dart test
cd packages/typed_graphql_codegen && dart test
cd packages/typed_graphql_builder && dart test
cd packages/typed_graphql_conformance && dart test
```

Expected: `All tests passed!` in each (the README tour test,
`test/doc/example_test.dart`, included).

- [ ] **Step 4: The API reference**

Run, in `packages/typed_graphql`: `dart doc`. Expected:
`Found 0 warnings and 0 errors.` (`doc/api/` is git-ignored).

- [ ] **Step 5: Publish dry-runs**

With a clean tree (`git status --short` prints nothing), run for each of
`typed_graphql`, `typed_graphql_server`, `typed_graphql_shelf`,
`typed_graphql_client`, `typed_graphql_codegen`, `typed_graphql_builder`:

```sh
cd packages/<package> && dart pub publish --dry-run
```

Expected: `Package has 0 warnings.` and exit code 0 for each. (A dirty tree
gives "1 checked-in file is modified in git" and exit 65: commit first.) Never
run it without `--dry-run`.

- [ ] **Step 6: Self-review**

1. `wc -l test/discovery/*.dart packages/typed_graphql/test/doc/markdown_links*.dart`:
   every file under 500 lines (the largest is about 100).
2. `git diff main --stat`: only the files of the file map changed.
3. Read the core README's "Should I use this?" against the "Claims" table and
   the current guides once more; read `llms.txt` against the README banners.
4. No sentence in the README, `llms.txt` or `docs/discovery.md` names, ranks
   or judges a third-party package.

Nothing to commit if every check passed.
