# M3c Core Documentation Catch-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document the core package `typed_graphql` as built by M1, M2 and M3a: six guides, a runnable example, a trimmed README and `dart doc` categories, with tests that run every program in a guide and compare what it prints.

**Architecture:** The guides are plain Markdown in `packages/typed_graphql/doc/`. Every fence tagged `dart` in them is a complete program; a test suite in `packages/typed_graphql/test/doc/` writes each one to a temporary file, runs it with the `dart` tool against the workspace packages and compares its output with the `text` fence that follows `It prints:`. The same suite checks that the programs are formatted, that links resolve, that no guide links to another file, that every exported type is in the dartdoc category of its folder, and that the README tour is `example/example.dart`. CI adds a `dart doc` run that must report 0 warnings.

**Tech Stack:** Dart 3.13 (`sdk: ^3.13.0`), `package:test`, `dart doc` (dartdoc categories through `dartdoc_options.yaml`), GitHub Actions. No new dependency: the `yaml` package is not used, the options file is read with regular expressions.

**Spec:** `docs/requirements.md` R11.1, R11.2, R11.3 (documentation requirements); `docs/superpowers/specs/2026-10-13-typed-graphql-design.md` (the architecture the guides describe); `docs/roadmap.md` (M3c is the catch-up for M1 to M3a; M3b documents its own work in the guides this plan creates, see "How M3b extends these guides").

## Global Constraints

- Minimum SDK `^3.13.0`; the programs in the guides run on SDK 3.13.0 and on stable (CI matrix) and print the same text on Linux, macOS and Windows (output is compared after `\r\n` to `\n` and trailing white space is trimmed).
- Repository text is English. Commit messages are Conventional Commits with the package as scope: `docs(typed_graphql): ...`, `test(typed_graphql): ...`, `ci: ...`.
- Code rules of `CLAUDE.md` apply to every Dart file of this plan (they live in `test/` and `example/`): no top-level function other than `main`, no `dynamic`, no `// ignore:`, a `catch` always has `on`, tests at most 500 lines, nesting at most 3, no `late` without a comment saying why.
- `dart format --output=none --set-exit-if-changed packages test` changes 0 files; `dart analyze --fatal-infos` at the root prints `No issues found!`; `dart test` at the root and in `packages/typed_graphql` pass; `dart doc` in `packages/typed_graphql` ends with `Found 0 warnings and 0 errors.`
- Every public member keeps its doc comment (`public_member_api_docs`); this plan adds only a `{@category ...}` tag to the existing doc comments of lib files, and no behaviour change.
- The documentation tests need the `dart` tool: `@TestOn('vm')`, and a self-skip when the test runs compiled (`--compiler exe` runs on `dartaotruntime`).
- No outward action: do not push, tag or publish. `dart pub publish` only with `--dry-run`.
- **Machine limits for every command** (a runaway `dart` process once used 22 GB and the kernel killed the whole session): run each test, analyze, doc or format command as `( ulimit -v 8000000; timeout 600 <command> )`, one heavy command at a time, and never several `dart test` runs in parallel. The snippet runner enforces its own limits (60 s and 512 MB per program, one program at a time). If a command is killed or times out, find the cause before going on.

## Review Focus

Failure modes the spec implies that a task's own tests would not otherwise catch. Each line names the task whose test pins it.

1. A guide program that compiles but whose printed text changes with the SDK (for example the text of a `FormatException`). The guides print only text owned by this package, and the CI matrix runs the suite on SDK 3.13.0 and stable. Pinned by the output assertion in Tasks 1, 3 to 7.
2. A relative link such as `schema.md` in a guide: it works on GitHub and breaks in `dart doc`. Tests refuse any relative link in a guide and make every README link resolve, anchors included (Task 2).
3. A program that never ends or eats memory (a guide edit, a regression in the parser). The runner kills it after 60 s, limits its heap to 512 MB and fails the test with `timed out`; a unit test runs a `while (true) {}` program with a 2 s limit (Task 1).
4. A new exported type without a `{@category}` tag, or a category with no guide, which dartdoc silently puts in the uncategorised bucket. `category_tags_test.dart` fails with the type's name (Task 8). This is how M3b and M4 are forced to document their types.
5. The suite run compiled (`--compiler exe`) or on the web: the tests are VM-only and skip themselves, and the AOT CI job stays green (Task 1 and Task 10 check it).
6. The README tour drifting from `example/example.dart` (Task 9), and a formatting slip in a guide program (Task 1: the format test).

## File Structure

Created, all under `packages/typed_graphql/` unless stated:

| File | Responsibility |
|---|---|
| `doc/getting_started.md` | The layers, install, a first program, the four rules |
| `doc/diagnostics.md` | `Source`, spans, excerpts, `DiagnosticCode`, `DiagnosticSink`, diagnostics to a response |
| `doc/protocol.md` | `JsonValue`, `JsonReader`, `DecodeResult`, `GraphQLRequest`, `GraphQLError`, `ResponsePayload` |
| `doc/language.md` | `Parser`, `Printer`, the syntax tree, visiting, transforming, schema coordinates, tokens |
| `doc/schema.md` | `SchemaBuilder`, `Schema`, the model, built-ins, SDL problems, extending, printing |
| `doc/scalars.md` | `ScalarCodec`, built-in codecs, `ScalarCodecs`, a custom codec, `LiteralConverter` |
| `dartdoc_options.yaml` | The dartdoc categories, each tied to its guide, and their order |
| `example/example.dart` | The README tour as a program (pub.dev shows it) |
| `test/doc/markdown_fence.dart` | `MarkdownFences`: the fenced blocks of a Markdown file with their preceding prose |
| `test/doc/doc_snippet.dart` | `DocSnippets`: the programs of a file and their expected output |
| `test/doc/snippet_runner.dart` | `SnippetRunner`: runs a program (bounded) and checks `dart format` |
| `test/doc/doc_files.dart` | `DocFiles`: which Markdown files the suite reads |
| `test/doc/doc_snippets_test.dart` | Every program runs, prints what the guide says, and is formatted |
| `test/doc/markdown_links.dart` | `MarkdownLinks`: relative links and heading anchors |
| `test/doc/doc_links_test.dart` | No relative link in a guide; every README link resolves |
| `test/doc/public_type.dart` | `PublicTypes`: the public types declared in a Dart file |
| `test/doc/category_tags_test.dart` | Categories, tags, guides and their order agree |
| `test/doc/example_test.dart` | The README tour equals `example/example.dart` |
| `test/doc/*_test.dart` for each helper | Unit tests of the helpers above |

Modified: the doc comments of 73 files in `lib/src/` (a `{@category ...}` line, by a script), `lib/typed_graphql.dart` (library category), `README.md` (trimmed), `CHANGELOG.md`; at the repository root `README.md` (Documentation section), `.gitignore` (`doc/api/`), `.github/workflows/ci.yml` (the `dart doc` step), `CLAUDE.md` (documentation rules).

### Decisions

- **Scalars is its own guide, not a section of schema.** `ScalarType` is plain schema data and the codec is deliberately not a field of it (R2.9): the server and the client register codecs by name. The two topics have different readers (someone who reads SDL, someone who writes a codec), different types (`lib/src/schema/scalars/` is its own folder with its own dartdoc category) and the schema guide is already the longest. The guides link to each other by topic name, never by path.
- **A program per fence, run as a program.** A fence tagged exactly `dart` is a complete program with its imports and `main`; the next fence, tagged `text` and introduced by a line ending in `It prints:`, is its exact output. A fragment or a signature is written in a `text` fence. A tag such as `dartpad` is an error, so a program cannot silently escape the test. A snippet is run by the `dart` tool in its own process because a test cannot compile a string; one process takes about 0.5 s, so the suite takes about 20 s.
- **Why not `dart doc`'s `{@tool dartpad}` or `package:markdown_snippets`.** They run no program and assert no output; the point here is that printed text cannot rot.
- **No relative links in guides.** `dart doc` renders a guide as a page of its own and `schema.md` becomes a broken URL. Guides name each other by topic ("see the Scalars & Codecs topic"); READMEs, which GitHub and pub.dev render, link by path.
- **`example/example.dart` uses `stdout.writeln`**, not `print`: the `avoid_print` lint is on and a lint is never silenced. It is the first program of the README, and a test keeps the two equal.
- **The `yaml` package is not added.** The options file has a fixed shape, which a test reads with regular expressions (dependencies arrive with the stage that needs them).
- **No `documentation:` key in `pubspec.yaml`.** pub.dev links the repository and the generated API reference already.
- **No stub READMEs for the six skeleton packages.** They have no exported API and a README that already says "skeleton"; there is nothing to document before M5.
- **`dart doc` output** goes to `doc/api/`, which is git-ignored; the doc tests read `doc/*.md` only, not recursively.
- The `show.dart` scratch tool used while writing the guides is not part of the plan.

### How M3b extends these guides

M3b (schema validation, introspection, coordinate resolution) writes its own documentation in the commit that adds the code; this plan leaves it a named place and no placeholder text.

- `doc/schema.md` ends with `## What building does not check`. M3b inserts `## Validating a schema` and `## Introspection` **before** that section, with programs that follow the rules above, and rewrites the last paragraph of "What building does not check" (the sentence "Checking a schema against the rules of the specification arrives in a later release of this package.") to point at the new sections by name.
- `doc/language.md` has `## Schema coordinates` (parsing and printing). M3b adds the resolving of a coordinate against a schema as a new `### Resolving a coordinate` subsection of `doc/schema.md`, because it needs a `Schema`, and mentions it in one sentence in the language guide without a link.
- M3b's new exported types need a `{@category ...}` tag in their doc comments or `category_tags_test.dart` fails. Types under `lib/src/schema/` take `{@category schema}`. If M3b places a type under `lib/src/validation/`, the test asks for a `validation` category: add it to `dartdoc_options.yaml` (with its `markdown:` guide, `displayName`, an entry in `categoryOrder`) and write `doc/validation.md`; the stage that first exports `validation/` types does this, and M4 (operation validation) will reuse it.
- The README status paragraph and `CHANGELOG.md` list M3b's additions in the same commit.

---

## Task 1: The program runner and the Getting Started guide

**Files:**
- Create: `packages/typed_graphql/test/doc/markdown_fence.dart`, `markdown_fence_test.dart`, `doc_snippet.dart`, `doc_snippet_test.dart`, `snippet_runner.dart`, `snippet_runner_test.dart`, `doc_files.dart`, `doc_snippets_test.dart`
- Create: `packages/typed_graphql/doc/getting_started.md`
- Modify: `packages/typed_graphql/README.md` (reflow one line of an existing program so the format test passes)

**Interfaces:**
- Produces: `MarkdownFences().of(String) -> List<MarkdownFence(info, body, line, precedingText)>`; `DocSnippets().of(String file, String markdown) -> List<DocSnippet(file, line, code, expectedOutput)>` with `place`; `SnippetRunner(packageConfig, directory, {timeLimit})` with `isAvailable`, `run(snippet, name) -> SnippetRun(exitCode, output, errors)`, `unformattedPlaces(snippets) -> List<String>`; `DocFiles().guides()` and `.all()` (path from the package folder to content). Later tasks add guides that these tests pick up by themselves.

- [ ] **Step 1: Write the failing unit tests of the fence and snippet readers**

Create `packages/typed_graphql/test/doc/markdown_fence_test.dart`:

````dart
import 'package:test/test.dart';

import 'markdown_fence.dart';

void main() {
  const fences = MarkdownFences();

  test('reads the tag, the body and the line of each fence', () {
    final found = fences.of('Intro.\n\n```dart\nvar a = 1;\nvar b = 2;\n```\n');
    expect(found, hasLength(1));
    expect(found.single.info, 'dart');
    expect(found.single.body, 'var a = 1;\nvar b = 2;');
    expect(found.single.line, 3);
  });

  test('keeps the prose between two fences as the preceding text', () {
    final found = fences.of(
      '```dart\na\n```\n\nIt prints:\n\n```text\nb\n```\n',
    );
    expect(found.last.precedingText, 'It prints:');
  });

  test('a fence with no tag has an empty info', () {
    expect(fences.of('```\nx\n```').single.info, '');
  });

  test('ignores lines that only look like fences when indented', () {
    expect(fences.of('  ```dart\n  x\n  ```'), isEmpty);
  });

  test('an unclosed fence is a FormatException', () {
    expect(
      () => fences.of('```dart\nvar a = 1;\n'),
      throwsA(isA<FormatException>()),
    );
  });
}
````

Create `packages/typed_graphql/test/doc/doc_snippet_test.dart`:

````dart
import 'package:test/test.dart';

import 'doc_snippet.dart';

void main() {
  const snippets = DocSnippets();

  test('a dart fence followed by "It prints:" has an expected output', () {
    final found = snippets.of(
      'a.md',
      '```dart\nmain() {}\n```\n\nIt prints:\n\n```text\nhi\n```\n',
    );
    expect(found, hasLength(1));
    expect(found.single.code, 'main() {}');
    expect(found.single.expectedOutput, 'hi');
    expect(found.single.place, 'a.md:1');
  });

  test('a dart fence with no output fence expects nothing', () {
    final found = snippets.of('a.md', '```dart\nmain() {}\n```\n');
    expect(found.single.expectedOutput, isNull);
  });

  test('a text fence that is not an output is not a program', () {
    expect(
      snippets.of('a.md', 'A signature:\n\n```text\nint f()\n```\n'),
      isEmpty,
    );
  });

  test('a text fence after "It prints:" with no program is an error', () {
    expect(
      () => snippets.of('a.md', 'It prints:\n\n```text\nhi\n```\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('a tag such as dartpad is an error, not a skipped program', () {
    expect(
      () => snippets.of('a.md', '```dartpad\nmain() {}\n```\n'),
      throwsA(isA<FormatException>()),
    );
  });
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc )`
Expected: FAIL to load, `Target of URI doesn't exist: 'markdown_fence.dart'`.

- [ ] **Step 3: Write the readers**

Create `packages/typed_graphql/test/doc/markdown_fence.dart`:

````dart
/// One fenced code block of a Markdown file.
final class MarkdownFence(
  /// The text after the opening backticks, such as `dart` or `text`.
  final String info,

  /// The lines inside the fence, joined with `\n`.
  final String body,

  /// The 1-based line of the opening backticks.
  final int line,

  /// The prose between the previous fence and this one, trimmed lines
  /// joined with `\n`; empty when the fences are only blank lines apart.
  final String precedingText,
) {
  /// Creates a fence.
  this;
}

/// Finds the fenced code blocks of Markdown text.
///
/// Only fences that start a line with three backticks are read, which is
/// how every guide writes them.
final class MarkdownFences {
  /// Creates the reader.
  const MarkdownFences();

  /// The fences of [markdown], in order. An unclosed fence is a
  /// [FormatException].
  List<MarkdownFence> of(String markdown) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final fences = <MarkdownFence>[];
    final prose = <String>[];
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      if (!line.startsWith('```')) {
        if (line.trim().isNotEmpty) prose.add(line.trim());
        index++;
        continue;
      }
      final closing = lines.indexOf('```', index + 1);
      if (closing < 0) {
        throw FormatException('Unclosed fence at line ${index + 1}');
      }
      fences.add(
        MarkdownFence(
          line.substring(3).trim(),
          lines.sublist(index + 1, closing).join('\n'),
          index + 1,
          prose.join('\n'),
        ),
      );
      prose.clear();
      index = closing + 1;
    }
    return fences;
  }
}
````

Create `packages/typed_graphql/test/doc/doc_snippet.dart`:

````dart
import 'markdown_fence.dart';

/// A complete Dart program in a guide, and the output the guide says it
/// prints.
final class DocSnippet(
  /// The Markdown file, from the package folder.
  final String file,

  /// The 1-based line of the snippet's opening fence.
  final int line,

  /// The program.
  final String code,

  /// What the guide says the program prints; null when it says nothing.
  final String? expectedOutput,
) {
  /// Creates a snippet.
  this;

  /// `file:line`, the place to look when the snippet fails.
  String get place => '$file:$line';
}

/// Finds the programs in a Markdown file.
///
/// Every fence tagged `dart` is a program: complete, with its imports and
/// `main`. A fence tagged `text` right after it, introduced by the line
/// `It prints:`, is its expected output. What is not a program, such as a
/// signature or a fragment, is written in a fence tagged `text`, or with
/// no tag.
final class DocSnippets {
  /// Creates the finder.
  const DocSnippets();

  /// The snippets of [markdown], the content of [file]. An output with no
  /// program before it, and a fence tagged `dart` plus anything else, are
  /// a [FormatException].
  List<DocSnippet> of(String file, String markdown) {
    final fences = const MarkdownFences().of(markdown);
    final snippets = <DocSnippet>[];
    for (final (index, fence) in fences.indexed) {
      if (fence.info.startsWith('dart') && fence.info != 'dart') {
        throw FormatException('$file:${fence.line}: tag "${fence.info}"');
      }
      if (_isOutput(fence) &&
          (index == 0 || fences[index - 1].info != 'dart')) {
        throw FormatException('$file:${fence.line}: output without a program');
      }
      if (fence.info == 'dart') {
        snippets.add(
          DocSnippet(
            file,
            fence.line,
            fence.body,
            index + 1 < fences.length && _isOutput(fences[index + 1])
                ? fences[index + 1].body
                : null,
          ),
        );
      }
    }
    return snippets;
  }

  bool _isOutput(MarkdownFence fence) =>
      fence.info == 'text' && fence.precedingText.endsWith('It prints:');
}
````

- [ ] **Step 4: Run the unit tests**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc )`
Expected: PASS (10 tests).

- [ ] **Step 5: Write the failing runner tests, then the runner**

The runner tests are the proof that a broken guide fails the suite: a program that does not compile, one that throws, one that never ends, one that is badly formatted.

Create `packages/typed_graphql/test/doc/snippet_runner_test.dart`:

````dart
@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import 'doc_snippet.dart';
import 'snippet_runner.dart';

/// The runner must fail a broken guide, or the doc tests prove nothing.
void main() {
  // `late`: `setUpAll` sets both before any test reads them; the package
  // configuration comes from a Future.
  late final Directory directory;
  late final SnippetRunner runner;

  // Compiled with `--compiler exe` there is no package configuration and
  // every test is skipped, so nothing is set up or removed.
  setUpAll(() async {
    if (!SnippetRunner.isAvailable) return;
    final configuration = await Isolate.packageConfig;
    directory = Directory.systemTemp.createTempSync('typed_graphql_runner_');
    runner = SnippetRunner(configuration!.toFilePath(), directory);
  });
  tearDownAll(() {
    if (SnippetRunner.isAvailable) directory.deleteSync(recursive: true);
  });

  final skip = SnippetRunner.isAvailable
      ? null
      : 'needs the dart tool, not a compiled test';

  DocSnippet program(String code) => DocSnippet('a.md', 1, code, null);

  test('gives the output of a program that runs', () async {
    final run = await runner.run(
      program(
        "import 'package:typed_graphql/typed_graphql.dart';\n"
        "void main() { print(Source('query { a }').body); }",
      ),
      'ok',
    );
    expect(run.exitCode, 0, reason: run.errors);
    expect(run.output, 'query { a }');
  }, skip: skip);

  test('reports a program that does not compile', () async {
    final run = await runner.run(program('void main() { missing(); }'), 'bad');
    expect(run.exitCode, isNot(0));
    expect(run.errors, contains('missing'));
  }, skip: skip);

  test('kills a program that runs past the time limit', () async {
    final impatient = SnippetRunner(
      runner.packageConfig,
      directory,
      timeLimit: const Duration(seconds: 2),
    );
    final run = await impatient.run(
      program('void main() { while (true) {} }'),
      'forever',
    );
    expect(run.exitCode, -1);
    expect(run.errors, contains('timed out'));
  }, skip: skip);

  test('names the programs dart format would change', () async {
    final places = await runner.unformattedPlaces([
      program('void main() {\n}'),
      program('void main() {}'),
    ]);
    expect(places, ['a.md:1']);
  }, skip: skip);

  test('reports a program that throws', () async {
    final run = await runner.run(
      program("void main() { throw StateError('no'); }"),
      'throws',
    );
    expect(run.exitCode, isNot(0));
    expect(run.errors, contains('Bad state: no'));
  }, skip: skip);
}
````

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/snippet_runner_test.dart )`
Expected: FAIL to load, `Target of URI doesn't exist: 'snippet_runner.dart'`.

Create `packages/typed_graphql/test/doc/snippet_runner.dart`:

````dart
import 'dart:convert';
import 'dart:io';

import 'doc_snippet.dart';

/// What running a snippet gave.
final class SnippetRun(
  /// The exit code; 0 when the program ran to its end.
  final int exitCode,

  /// Standard output, with `\n` line ends and no trailing white space.
  final String output,

  /// Standard error: the compile errors, or the uncaught exception.
  final String errors,
) {
  /// Creates a result.
  this;
}

/// Runs a [DocSnippet] as its own program, against this workspace's
/// packages.
///
/// It starts the `dart` executable that runs the tests, so it cannot work
/// in a test compiled with `--compiler exe`: [isAvailable] tells.
final class SnippetRunner(
  /// The `package_config.json` the program resolves `package:` imports with.
  final String packageConfig,

  /// A folder to write the programs to; the caller deletes it.
  final Directory directory, {

  /// How long a program may run before it is killed; a guide's program
  /// takes about a second.
  final Duration timeLimit = const Duration(seconds: 60),
}) {
  /// Creates a runner.
  this;

  /// Whether the running test is the `dart` tool itself, not an executable
  /// compiled from the test.
  ///
  /// A test compiled with `--compiler exe` runs on `dartaotruntime`, which
  /// cannot run a source file, so the name must be exactly `dart`.
  static bool get isAvailable => const [
    'dart',
    'dart.exe',
  ].contains(Platform.resolvedExecutable.split(RegExp(r'[/\\]')).last);

  /// The heap a program may use, in megabytes: a runaway program fails
  /// by itself instead of taking the machine's memory.
  static const int heapLimit = 512;

  /// Writes [snippet] to `<name>.dart` and runs it, alone, within
  /// [timeLimit] and [heapLimit]. A program that runs too long is killed
  /// and gives exit code -1.
  Future<SnippetRun> run(DocSnippet snippet, String name) async {
    final program = File('${directory.path}/$name.dart')
      ..writeAsStringSync('${snippet.code}\n');
    final process = await Process.start(Platform.resolvedExecutable, [
      '--old-gen-heap-size=$heapLimit',
      '--packages=$packageConfig',
      program.path,
    ]);
    final output = utf8.decodeStream(process.stdout);
    final errors = utf8.decodeStream(process.stderr);
    final exitCode = await process.exitCode.timeout(
      timeLimit,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    return SnippetRun(
      exitCode,
      _normalized(await output),
      _normalized(
        exitCode == -1 ? 'timed out after $timeLimit' : await errors,
      ),
    );
  }

  /// The places of the [snippets] that `dart format` would change, found
  /// by one `dart format` run over all of them.
  Future<List<String>> unformattedPlaces(List<DocSnippet> snippets) async {
    final folder = Directory('${directory.path}/format')..createSync();
    for (final (index, snippet) in snippets.indexed) {
      File('${folder.path}/s$index.dart')
          .writeAsStringSync('${snippet.code}\n');
    }
    final result = await Process.run(Platform.resolvedExecutable, [
      'format',
      '--output=none',
      folder.path,
    ]).timeout(timeLimit);
    return [
      for (final match in RegExp(
        r'^Changed .*s(\d+)\.dart$',
        multiLine: true,
      ).allMatches('${result.stdout}'.replaceAll('\r\n', '\n')))
        snippets[int.parse(match[1]!)].place,
    ];
  }

  /// [text] with `\n` line ends and without trailing white space, so the
  /// comparison does not depend on the platform.
  static String _normalized(String text) =>
      text.replaceAll('\r\n', '\n').trimRight();
}
````

Run the same command again.
Expected: PASS (5 tests, about 3 s: the runaway program is killed after 2 s).

- [ ] **Step 6: Write the guide test and the file reader**

Create `packages/typed_graphql/test/doc/doc_files.dart`:

````dart
import 'dart:io';

/// The Markdown files the documentation tests read, from the package
/// folder, which is where `dart test` runs: the guides in `doc/`, the
/// package README and the repository README.
final class DocFiles {
  /// Creates the reader.
  const DocFiles();

  /// The guides, `doc/*.md`, keyed by their path from the package folder,
  /// in name order.
  Map<String, String> guides() => _read(
    Directory('doc')
        .listSync()
        .whereType<File>()
        .map((file) => file.path.replaceAll(r'\', '/'))
        .where((path) => path.endsWith('.md')),
  );

  /// The guides and the two READMEs, keyed by their path from the package
  /// folder.
  Map<String, String> all() => {
    ...guides(),
    ..._read(const ['README.md', '../../README.md']),
  };

  Map<String, String> _read(Iterable<String> paths) => {
    for (final path in paths.toList()..sort())
      path: File(path).readAsStringSync(),
  };
}
````

Create `packages/typed_graphql/test/doc/doc_snippets_test.dart`:

````dart
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
````

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/doc_snippets_test.dart )`
Expected: FAIL, `FileSystemException: Directory listing failed ... path = 'doc'`: the guides folder does not exist yet.

- [ ] **Step 7: Write the Getting Started guide**

Create `packages/typed_graphql/doc/getting_started.md`:

````markdown
# Getting Started

`typed_graphql` is the core of [typed_graphql](https://github.com/4akloon/graphql_dart),
GraphQL for Dart written from scratch and fully typed. It reads, checks,
prints and transforms GraphQL, and it speaks the wire format. It is pure
Dart, depends only on `meta`, and runs on the VM, AOT, dart2js and dart2wasm.

The package is built in layers. A layer imports only the layers before it:

| Layer | Topic | What it gives you |
|---|---|---|
| diagnostics | **Diagnostics** | `Source`, `SourceSpan`, `Diagnostic`, `DiagnosticCode`, `DiagnosticSink` |
| language | **Language** | `Parser`, `Printer`, the syntax tree, `AstWalker`, `AstTransformer`, schema coordinates |
| protocol | **Wire Protocol** | `JsonValue`, `JsonReader`, `GraphQLRequest`, `ResponsePayload`, `GraphQLError` |
| schema | **Schema**, **Scalars & Codecs** | `Schema`, `SchemaBuilder`, `SchemaPrinter`, `ScalarCodec` |

Everything is exported from one library, `package:typed_graphql/typed_graphql.dart`.

## Install

Nothing is on pub.dev yet. To use it from the repository:

```yaml
dependencies:
  typed_graphql:
    git:
      url: https://github.com/4akloon/graphql_dart
      path: packages/typed_graphql
```

## A first program

Parse an operation and print it the way graphql-js does, then build a schema
from SDL:

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  final query = Source('query Hero { hero { name } }', name: 'hero.graphql');
  if (parser.parse(query) case ParseSuccess(:final document)) {
    print(const Printer().print(document));
  }

  final sdl = Source('type Query { hero: String }', name: 'schema.graphql');
  final result = const SchemaBuilder().fromSdl(
    parser.parse(sdl).requireDocument(),
    source: sdl,
  );
  switch (result) {
    case BuildSuccess(:final schema):
      print('query root: ${schema.queryTypeName}');
    case BuildFailure(:final diagnostics):
      diagnostics.forEach(print);
  }
}
```

It prints:

```text
query Hero {
  hero {
    name
  }
}
query root: Query
```

## Four rules

- **Bad input never throws.** A syntax error, an invalid schema or a mistyped
  JSON body becomes a value you inspect: a diagnostic or a `DecodeFailure`.
  Exceptions are for programmer errors only (`ArgumentError`, `StateError`).
- **Results are sealed.** `ParseSuccess` or `ParseFailure`, `BuildSuccess` or
  `BuildFailure`, `DecodeSuccess` or `DecodeFailure`: a `switch` over them is
  checked by the compiler, and a failure carries what was built from the rest.
- **Every problem has a code and a place.** A `Diagnostic` has a stable id
  (`GQL008`), a message and the span of the source it is about. All of them
  are reported in one pass, not only the first.
- **No `dynamic`.** Arbitrary JSON is a `JsonValue`, a sealed family you can
  switch over.

## Where to go next

- **Language** — parse, print, walk and rewrite documents; schema coordinates.
- **Diagnostics** — sources, spans, codes, and how to report your own.
- **Wire Protocol** — requests, responses and errors as typed values.
- **Schema** — build a schema from SDL, extend it, print it.
- **Scalars & Codecs** — the built-in scalar codecs and your own.

The API reference lists every type under the same topics.
````

In `packages/typed_graphql/README.md`, one existing program has a line that `dart format` would break; reflow it. Replace

```text
  final extension = Source('extend type Droid { id: ID }', name: 'more.graphql');
```

with

```text
  final extension = Source(
    'extend type Droid { id: ID }',
    name: 'more.graphql',
  );
```

- [ ] **Step 8: Run the guide test and see it catch a wrong guide**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/doc_snippets_test.dart )`
Expected: PASS: every program of `doc/getting_started.md`, `README.md` and the root `README.md` runs, prints what the text says and is formatted.

Then prove the test can fail: change `query root: Query` in the guide's output fence to `query root: Mutation`, run the command again, expect FAIL at `doc/getting_started.md:36 prints what the guide says` with the expected and the actual text side by side, and change it back. (The line is the program's opening fence.)

- [ ] **Step 9: Format, analyze, and check the compiled run**

Run, one at a time, from the repository root:
- `( ulimit -v 8000000; timeout 600 dart format --output=none --set-exit-if-changed packages test )` — 0 changed.
- `( ulimit -v 8000000; timeout 600 dart analyze --fatal-infos )` — `No issues found!`
- `( ulimit -v 8000000; timeout 600 dart test )` — the code rules pass (all test files stay under 500 lines).

Then, from `packages/typed_graphql`: `( ulimit -v 8000000; timeout 600 dart test --compiler exe -j 1 test/doc )`
Expected: PASS with the program tests skipped (`~`): under `--compiler exe` the test runs on `dartaotruntime`, which `SnippetRunner.isAvailable` refuses.

- [ ] **Step 10: Commit**

```bash
git add packages/typed_graphql/test/doc packages/typed_graphql/doc/getting_started.md packages/typed_graphql/README.md
git commit -m "test(typed_graphql): run the programs in the guides

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Task 2: Link checks

**Files:**
- Create: `packages/typed_graphql/test/doc/markdown_links.dart`, `markdown_links_test.dart`, `doc_links_test.dart`

**Interfaces:**
- Consumes: `DocFiles().guides()` and `.all()` from Task 1.
- Produces: `MarkdownLinks().relativeIn(String) -> List<MarkdownLink(line, target)>` and `.anchorsIn(String) -> Set<String>` (GitHub anchor rules: lower case, punctuation removed, spaces to hyphens, `-1`, `-2` for repeats; fenced code ignored).

- [ ] **Step 1: Write the failing unit test**

Create `packages/typed_graphql/test/doc/markdown_links_test.dart`:

````dart
import 'package:test/test.dart';

import 'markdown_links.dart';

void main() {
  const links = MarkdownLinks();

  test('finds relative links and their lines, and skips web links', () {
    final found = links.relativeIn(
      'See [a](doc/a.md) and [b](https://x.dev/b).\n[c](#top)\n',
    );
    expect(found.map((link) => link.target), ['doc/a.md', '#top']);
    expect(found.map((link) => link.line), [1, 2]);
  });

  test('leaves out links inside fenced code', () {
    expect(links.relativeIn('```text\n[a](b.md)\n```\n'), isEmpty);
  });

  test('turns headings into GitHub anchors', () {
    expect(
      links.anchorsIn('# Scalars & Codecs\n\n## What it does, 1\n'),
      {'scalars--codecs', 'what-it-does-1'},
    );
  });

  test('numbers the anchors of a repeated heading', () {
    expect(links.anchorsIn('## Same\n\n## Same\n'), {'same', 'same-1'});
  });

  test('a comment line in a fence is not a heading', () {
    expect(links.anchorsIn('```text\n# not a heading\n```\n'), isEmpty);
  });
}
````

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/markdown_links_test.dart )`
Expected: FAIL to load, `Target of URI doesn't exist: 'markdown_links.dart'`.

- [ ] **Step 2: Write the link reader**

Create `packages/typed_graphql/test/doc/markdown_links.dart`:

````dart
/// A link to a place in the repository, as a Markdown file writes it.
final class MarkdownLink(
  /// The 1-based line of the link in its file.
  final int line,

  /// What follows `](`: a path, a path with `#anchor`, or just `#anchor`.
  final String target,
) {
  /// Creates a link.
  this;
}

/// Finds the relative links and the anchors of Markdown text. Web links
/// are left alone: the tests run offline.
final class MarkdownLinks {
  /// Creates the reader.
  const MarkdownLinks();

  static final RegExp _link = RegExp(r'\[[^\]]*\]\(([^)\s]+)\)');
  static final RegExp _heading = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$');
  static final RegExp _web = RegExp('^(?:[a-z][a-z0-9+.-]*:)');

  /// The links of [markdown] that point inside the repository, fenced code
  /// left out.
  List<MarkdownLink> relativeIn(String markdown) => [
    for (final (index, line) in _prose(markdown).indexed)
      for (final match in _link.allMatches(line))
        if (!_web.hasMatch(match[1]!)) MarkdownLink(index + 1, match[1]!),
  ];

  /// The anchors GitHub gives the headings of [markdown]: the text in
  /// lower case without punctuation, spaces as hyphens, `-1`, `-2` for a
  /// repeated heading.
  Set<String> anchorsIn(String markdown) {
    final counts = <String, int>{};
    final anchors = <String>{};
    for (final line in _prose(markdown)) {
      final text = _heading.firstMatch(line)?[1];
      if (text == null) continue;
      final slug = text
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9 _-]'), '')
          .replaceAll(' ', '-');
      final seen = counts[slug] ?? 0;
      counts[slug] = seen + 1;
      anchors.add(seen == 0 ? slug : '$slug-$seen');
    }
    return anchors;
  }

  /// The lines of [markdown], with those inside a fence blanked so that
  /// line numbers stay.
  List<String> _prose(String markdown) {
    var isFenced = false;
    final lines = <String>[];
    for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
      if (line.startsWith('```')) {
        isFenced = !isFenced;
        lines.add('');
      } else {
        lines.add(isFenced ? '' : line);
      }
    }
    return lines;
  }
}
````

Run the same command. Expected: PASS (5 tests).

- [ ] **Step 3: Write the link test**

It makes two promises: a guide has no relative link at all (dartdoc would break it), and every relative link of a README or a guide resolves to a file, and to a heading when it has `#anchor`.

Create `packages/typed_graphql/test/doc/doc_links_test.dart`:

````dart
@TestOn('vm')
library;

import 'dart:io';

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
          final uri = Uri.parse(path).resolve(target);
          expect(
            FileSystemEntity.typeSync(uri.path),
            isNot(FileSystemEntityType.notFound),
          );
          if (uri.fragment.isNotEmpty) {
            final anchors = links.anchorsIn(File(uri.path).readAsStringSync());
            expect(anchors, contains(uri.fragment));
          }
        });
      }
    }
  });
}
````

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/doc_links_test.dart )`
Expected: PASS. Prove it can fail: in the package `README.md` change `(#install)` to `(#instal)`, expect FAIL at `README.md:<line> -> #instal`, and change it back.

- [ ] **Step 4: Format, analyze, commit**

Run `dart format --output=none --set-exit-if-changed packages test` and `dart analyze --fatal-infos` from the root (each wrapped in `( ulimit -v 8000000; timeout 600 ... )`): both clean.

```bash
git add packages/typed_graphql/test/doc
git commit -m "test(typed_graphql): check the links of the guides and READMEs

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Task 3: The Diagnostics guide

**Files:**
- Create: `packages/typed_graphql/doc/diagnostics.md`

**Interfaces:**
- Consumes: the doc test suite of Tasks 1 and 2, which picks the new guide up by itself.
- Produces: a guide named "Diagnostics" (the dartdoc category `diagnostics` of Task 8 points at this file). Facts it states, all checked by its programs: spans and excerpts, `GQL000` on the sink limit, `maxErrors`, diagnostics to a `RequestErrorResult`.

- [ ] **Step 1: Write the guide**

Every program is complete and its output was produced by running it against the code of this commit. Do not edit an output by hand: if a program prints something else, the guide is wrong or the code regressed, and the test says which.

Create `packages/typed_graphql/doc/diagnostics.md`:

````markdown
# Diagnostics

Every problem the package finds in a document, a schema or a payload is a
`Diagnostic`: a stable code, a severity, a message for people and the place in
the source it is about. Parsing and building a schema return diagnostics
instead of throwing, and validation will report through the same model.

## Sources and spans

A `Source` is the text of a document and the name diagnostics show for it.
`locationOf(offset)` gives a 1-based line and column; the column counts
UTF-16 code units, as `String.codeUnitAt` does. A line ends with `\n`, `\r\n`
or `\r`.

A `SourceSpan` is a range of a `Source`: offsets from `start` up to, not
including, `end`. Its `location` is the line and column of `start`, its `text`
is the text it covers, and its `excerpt` shows the line the way graphql-js's
`printLocation` does.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('{\n  hero {\n    name\n  }\n}', name: 'hero.graphql');

  print(source.locationOf(15));
  final span = SourceSpan(source, 15, 19);
  print(span);
  print(span.text);
  print(span.excerpt);
}
```

It prints:

```text
3:5
hero.graphql:3:5
name
hero.graphql:3:5
2 |   hero {
3 |     name
  |     ^
4 |   }
```

The table of line starts is built on the first call to `locationOf`, so a
document that reports nothing is never scanned for lines.

## Reading a diagnostic

A `Diagnostic` has a `code` (a `DiagnosticCode`), a `severity`
(`DiagnosticSeverity.error` or `warning`), a `message`, the `span` it is about
(null when it has no place in a source) and `related` spans that explain it,
such as the first definition of a duplicated name. Two diagnostics are equal
when all five are, so a test can compare lists of them.

`toString` gives the form terminals and editors link to:
`name:line:column: severity GQLnnn: message`.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final broken = Source(
    'query { a(x: ) }\nfragment F on { b }',
    name: 'bad.graphql',
  );
  for (final diagnostic in const Parser().parse(broken).diagnostics) {
    print(diagnostic);
    print('  ${diagnostic.code.id}, error: ${diagnostic.isError}');
  }

  final twice = Source(
    'type A { a: Int }\ntype A { b: Int }',
    name: 'dup.graphql',
  );
  final built = const SchemaBuilder().fromSdl(
    const Parser().parse(twice).requireDocument(),
    source: twice,
  );
  final duplicate = built.diagnostics.single;
  print(duplicate);
  print('first one at ${duplicate.related.single}');
  print('locations ${duplicate.locations}');
}
```

It prints:

```text
bad.graphql:1:14: error GQL008: Unexpected ")".
  GQL008, error: true
bad.graphql:2:15: error GQL007: Expected Name, found "{".
  GQL007, error: true
dup.graphql:2:6: error GQL101: There can be only one type named "A".
first one at dup.graphql:1:1
locations [2:6, 1:1]
```

## Codes

`DiagnosticCode` is the catalog: one value per problem, each with an `id`
such as `GQL008` and a doc comment that says when it is reported. The hundreds
digit is the area:

| Ids | Area |
|---|---|
| `GQL0xx` | lexer and syntax |
| `GQL1xx` | type system: building a schema |
| `GQL2xx` | operation validation |
| `GQL3xx` | coercion and execution |
| `GQL4xx` | transports and protocols |
| `GQL5xx` | code generation |

`GQL000` belongs to no area: a sink reports it when its limit is reached. An id
is public API and is never renumbered, reused or removed. New releases add
codes, so do not switch over `DiagnosticCode` exhaustively; match the codes you
handle and keep a wildcard.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('query { a(x: ) }', name: 'bad.graphql');
  for (final diagnostic in const Parser().parse(source).diagnostics) {
    final advice = switch (diagnostic.code) {
      DiagnosticCode.unexpectedToken => 'a value is missing',
      DiagnosticCode.tokenLimitExceeded => 'the document is too long',
      _ => 'see ${diagnostic.code.id}',
    };
    print('${diagnostic.code.id}: $advice');
  }
}
```

It prints:

```text
GQL008: a value is missing
```

## Collecting diagnostics

A `DiagnosticSink` collects diagnostics in the order they are reported; the
order is never changed. It keeps at most `maxErrors` errors (100 by default,
the limit graphql-js uses for validation). The next error adds one
`GQL000` error instead, `isFull` becomes true and every later report is
ignored, so a hostile document cannot produce an unbounded list. Warnings do
not count against the limit.

The lexer, the parser and the schema builder have a sink inside; their public
API turns it into a sealed result. Use a sink yourself when you write a check
of your own:

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('type A\ntype B\ntype C', name: 'types.graphql');
  final sink = DiagnosticSink(maxErrors: 2);
  for (final (index, name) in ['A', 'B', 'C'].indexed) {
    final start = source.body.indexOf('type $name') + 5;
    sink.report(
      Diagnostic(
        DiagnosticCode.duplicateTypeName,
        DiagnosticSeverity.error,
        'There can be only one type named "$name".',
        span: SourceSpan(source, start, start + 1),
      ),
    );
  }
  sink.diagnostics.forEach(print);
  print('hasErrors: ${sink.hasErrors}, isFull: ${sink.isFull}');
}
```

It prints:

```text
types.graphql:1:6: error GQL101: There can be only one type named "A".
types.graphql:2:6: error GQL101: There can be only one type named "B".
types.graphql:3:6: error GQL000: Too many errors: the limit of 2 was reached and the rest are not reported.
hasErrors: true, isFull: true
```

## Diagnostics on the wire

A diagnostic becomes the `GraphQLError` of a response: `locations` lists the
line and column of the span and then of each related span, which is the shape
the specification gives an error's `locations`. See the Wire Protocol topic
for the response types.

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('{ hero(id: ) }');
  final failure = const Parser().parse(source);
  final response = RequestErrorResult(
    errors: [
      for (final diagnostic in failure.diagnostics)
        GraphQLError(
          diagnostic.message,
          locations: diagnostic.locations,
          extensions: JsonObject({'code': JsonString(diagnostic.code.id)}),
        ),
    ],
  );
  print(jsonEncode(response.toJson()));
}
```

It prints:

```text
{"errors":[{"message":"Unexpected \")\".","locations":[{"line":1,"column":12}],"extensions":{"code":"GQL008"}}]}
```
````

- [ ] **Step 2: Run the guide tests**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/doc_snippets_test.dart test/doc/doc_links_test.dart )`
Expected: PASS; the new tests are named `doc/diagnostics.md:<line> runs`, `... prints what the guide says`.

- [ ] **Step 3: Commit**

```bash
git add packages/typed_graphql/doc/diagnostics.md
git commit -m "docs(typed_graphql): add the Diagnostics guide

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Task 4: The Wire Protocol guide

**Files:**
- Create: `packages/typed_graphql/doc/protocol.md`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: the guide "Wire Protocol" (category `protocol`). It states: `JsonValue` is a sealed family compared by value, `JsonReader` and `DecodeFailure` paths, `GraphQLRequest`, `GraphQLError`, `ResponsePayload` read with `decode` and written with `toJson`.

- [ ] **Step 1: Write the guide**

Create `packages/typed_graphql/doc/protocol.md`:

````markdown
# Wire Protocol

The protocol layer is the GraphQL wire format as typed values: a request, a
response and an error, and `JsonValue`, the type of any JSON. Reading
untrusted input never throws; it gives a `DecodeResult`.

## JsonValue

`JsonValue` is a sealed family: `JsonNull`, `JsonBool`, `JsonNumber`,
`JsonString`, `JsonArray` and `JsonObject`. It is the type of arbitrary JSON in
every public signature, so a `switch` over it is checked by the compiler and
there is no `dynamic`.

Values are immutable and compare by value: arrays item by item, objects by
keys and values whatever their order. Every number is one `JsonNumber`, because
the web cannot tell `1` from `1.0`; `asInt` reads a whole number no larger than
2^53 - 1 the same way on every platform and is null otherwise. `toJson()` gives
plain Dart objects that `jsonEncode` writes, and `toString()` is compact JSON.

```dart
import 'package:typed_graphql/typed_graphql.dart';

String describe(JsonValue value) => switch (value) {
  JsonNull() => 'null',
  JsonBool(:final value) => 'a boolean: $value',
  JsonNumber(:final asInt?) => 'a whole number: $asInt',
  JsonNumber(:final value) => 'a number: $value',
  JsonString(:final value) => 'a string of ${value.length} units',
  JsonArray(:final items) => 'an array of ${items.length}',
  JsonObject(:final fields) => 'an object with ${fields.keys.join(', ')}',
};

void main() {
  final values = [
    const JsonNull(),
    const JsonBool(true),
    JsonNumber(3),
    JsonNumber(2.5),
    const JsonString('hero'),
    JsonArray([JsonNumber(1), JsonNumber(2)]),
    JsonObject({'id': JsonNumber(7), 'tags': JsonArray([])}),
  ];
  values.map(describe).forEach(print);

  print(JsonNumber(1) == JsonNumber(1.0));
  print(JsonObject({'a': JsonNumber(1), 'b': JsonNull()}));
}
```

It prints:

```text
null
a boolean: true
a whole number: 3
a number: 2.5
a string of 4 units
an array of 2
an object with id, tags
true
{"a":1,"b":null}
```

## Reading JSON

`JsonReader` turns untrusted input into a `JsonValue`: `parse(text)` reads JSON
text, `read(object)` reads the output of `jsonDecode` or any plain Dart
objects. Bad input is a `DecodeFailure`: text that is not JSON, a number too
large to be finite (`1e400`), a map key that is not a string, and arrays and
objects nested deeper than `maxDepth` (512 by default, at most 1000). A key
repeated in one object keeps its last value, as `jsonDecode` does.

The depth is measured on the text before `jsonDecode` runs, because on the web
`jsonDecode` recurses once per level and would overflow the stack first.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const reader = JsonReader(maxDepth: 3);

  print(reader.parse('{"a": [1, 2]}'));
  print(reader.parse('{"a": ') is DecodeFailure);
  print(reader.parse('[1e400]'));
  print(reader.parse('[[[[1]]]]'));
  print(reader.read({'a': Object()}));
}
```

It prints:

```text
DecodeSuccess({"a":[1,2]})
true
$[0]: Infinity is not a finite number
$: arrays and objects are nested deeper than 3
$.a: not a JSON value
```

## Decode results

`DecodeResult<T>` is `DecodeSuccess<T>(value)` or `DecodeFailure(message,
path:)`. The `path` is a list of `PathSegment`s, a `PathKey(name)` for an object
key or a `PathIndex(index)` for an array item, from the root of the input to the
bad value; `toString` writes it as JSONPath. `inside(segment)` puts a failure
inside its parent, which is how a decoder of nested values builds the path.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const failure = DecodeFailure(
    'expected a string',
    path: [PathKey('errors'), PathIndex(0), PathKey('message')],
  );
  print(failure);

  const inner = DecodeFailure('expected a number');
  print(inner.inside(const PathIndex(2)).inside(const PathKey('ids')));
}
```

It prints:

```text
$.errors[0].message: expected a string
$.ids[2]: expected a number
```

## Requests

`GraphQLRequest` is a request as it travels over a transport: the body of a
GraphQL over HTTP POST, the payload of a graphql-ws `subscribe` message. Every
field is optional: `query`, `operationName`, `variables` and `extensions` (an
automatic persisted query sends only a hash in `extensions`). `decode` ignores
unknown keys, as GraphQL over HTTP requires, and fails on a mistyped field.
`toJson()` writes the fields that are set. Two requests are equal when their
JSON is.

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const reader = JsonReader();
  const body =
      '{"query": "query Hero(\$id: ID!) { hero(id: \$id) { name } }",'
      ' "variables": {"id": "1002"}, "clientTag": "web"}';

  if (reader.parse(body) case DecodeSuccess(:final value)) {
    switch (GraphQLRequest.decode(value)) {
      case DecodeSuccess(value: GraphQLRequest(:final query, :final variables)):
        print(query);
        print(variables);
      case final DecodeFailure failure:
        print(failure);
    }
  }

  const request = GraphQLRequest(
    query: '{ hero { name } }',
    operationName: 'Hero',
  );
  print(jsonEncode(request.toJson()));

  print(GraphQLRequest.decode(JsonObject({'variables': JsonArray([])})));
}
```

It prints:

```text
query Hero($id: ID!) { hero(id: $id) { name } }
{"id":"1002"}
{"query":"{ hero { name } }","operationName":"Hero"}
$.variables: expected an object
```

## Errors

`GraphQLError` is an error of a response, in the format of the specification:
a `message`, the `locations` in the document it is about, the response `path`
of the field it is about (response names and list indexes from the root of
`data`) and `extensions`. A server writes it with `toJson()`; a client reads it
with `decode`. Two errors are equal when their JSON is.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final error = GraphQLError(
    'Name for character with ID 1002 could not be fetched.',
    locations: [const SourceLocation(6, 7)],
    path: [
      const PathKey('hero'),
      const PathKey('friends'),
      const PathIndex(1),
      const PathKey('name'),
    ],
    extensions: JsonObject({'code': const JsonString('NOT_FOUND')}),
  );
  print(error.toJson());

  final decoded = GraphQLError.decode(error.toJson());
  print(decoded == DecodeSuccess(error));

  print(GraphQLError.decode(JsonObject({'message': JsonNumber(7)})));
}
```

It prints:

```text
{"message":"Name for character with ID 1002 could not be fetched.","locations":[{"line":6,"column":7}],"path":["hero","friends",1,"name"],"extensions":{"code":"NOT_FOUND"}}
true
$.message: expected a string
```

## Responses

`ResponsePayload` is the body of a response: an `ExecutionResult` when the
operation ran, a `RequestErrorResult` when it did not. `ResponsePayload.decode`
tells them apart by the `data` key.

- `ExecutionResult` has `data` (null when an error left none), `errors` and
  `extensions`. Data and errors together are a partial result.
- `RequestErrorResult` is a request that failed before it ran, such as a syntax
  or validation error: no `data`, at least one error (an empty list is an
  `ArgumentError`).

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const body = '''
{
  "errors": [
    {
      "message": "Name for character with ID 1002 could not be fetched.",
      "locations": [{"line": 6, "column": 7}],
      "path": ["hero", "friends", 1, "name"]
    }
  ],
  "data": {"hero": {"name": "R2-D2", "friends": [null, null]}}
}''';

  final payload = switch (const JsonReader().parse(body)) {
    DecodeSuccess(:final value) => ResponsePayload.decode(value),
    final DecodeFailure failure => failure,
  };
  switch (payload) {
    case DecodeSuccess(value: ExecutionResult(:final data, :final errors)):
      print('data: $data');
      print('first error at ${errors.first.path}');
    case DecodeSuccess(value: RequestErrorResult(:final errors)):
      print('the request failed: ${errors.first.message}');
    case final DecodeFailure failure:
      print('not a GraphQL response: $failure');
  }

  final failed = ResponsePayload.decode(
    JsonObject({
      'errors': JsonArray([
        GraphQLError('Syntax Error: Unexpected ")".').toJson(),
      ]),
    }),
  );
  print(failed);
}
```

It prints:

```text
data: {"hero":{"name":"R2-D2","friends":[null,null]}}
first error at [hero, friends, 1, name]
DecodeSuccess(RequestErrorResult({"errors":[{"message":"Syntax Error: Unexpected \")\"."}]}))
```
````

- [ ] **Step 2: Run the guide tests**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/doc_snippets_test.dart test/doc/doc_links_test.dart )`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add packages/typed_graphql/doc/protocol.md
git commit -m "docs(typed_graphql): add the Wire Protocol guide

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Task 5: The Language guide

**Files:**
- Create: `packages/typed_graphql/doc/language.md`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: the guide "Language" (category `language`), the longest one (about 550 lines, no size limit applies to Markdown). It states: parse results and limits (`maxTokens`, `maxDepth`), working-draft switches, the tree, `parseValue` and `parseTypeRef`, printing in both forms, `AstWalker`, `ParallelVisitor`, `AstTransformer`, schema coordinates, `Lexer`. It has a `## Schema coordinates` section which M3b extends (see "How M3b extends these guides").

- [ ] **Step 1: Write the guide**

Create `packages/typed_graphql/doc/language.md`:

````markdown
# Language

The language layer reads and writes GraphQL text, the September2025 grammar,
and gives you the document as a typed syntax tree: a lexer, an error-resilient
parser, a printer that matches graphql-js to the character, visitors, a
transformer and schema coordinates.

## Parsing a document

`Parser().parse(source)` turns a `Source` into a `ParseResult`:

- `ParseSuccess(document)` when the text has no syntax error.
- `ParseFailure(partial, diagnostics)` when it has. After an error the parser
  skips to the next definition or selection and goes on, so one pass reports
  every error. `partial` holds the definitions that parsed completely; the tree
  never contains an error node.

Both carry `diagnostics`, in report order. `requireDocument()` gives the
document or throws a `GraphQLSyntaxException` with the diagnostics, which is
convenient in tests and scripts. A `Parser` is `const` and keeps no state.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();
  final source = Source(
    'query A { a(x: ) }\nquery B { b }',
    name: 'two.graphql',
  );

  switch (parser.parse(source)) {
    case ParseSuccess():
      print('no errors');
    case ParseFailure(:final partial, :final diagnostics):
      diagnostics.forEach(print);
      print('${partial.definitions.length} definition kept');
  }

  try {
    parser.parse(source).requireDocument();
  } on GraphQLSyntaxException catch (exception) {
    print('${exception.diagnostics.length} diagnostic');
  }
}
```

It prints:

```text
two.graphql:1:16: error GQL008: Unexpected ")".
1 definition kept
1 diagnostic
```

### Limits and the working draft

`ParserOptions` bound the work on untrusted text: `maxTokens` (15 000 by
default) and `maxDepth` (128), the nesting of selection sets, lists and
objects. `null` removes a limit, which lets a hostile document exhaust memory
or the stack. The parser recurses on nested values, so a `maxDepth` near 1000
can overflow the stack on deeply nested object values; keep the default unless
you know the input.

Syntax from the specification's working draft is off by default and reported as
`GQL014` when used: `allowDirectiveExtensions` for `extend directive`,
directives on a directive definition and the `DIRECTIVE_DEFINITION` location,
and `allowEmptySelectionSets` for `{ }`.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const tiny = Parser(options: ParserOptions(maxTokens: 4));
  tiny.parse(Source('{ a b c d e }')).diagnostics.forEach(print);

  const shallow = Parser(options: ParserOptions(maxDepth: 2));
  shallow.parse(Source('{ a { b { c } } }')).diagnostics.forEach(print);

  final extension = Source('extend directive @tag @deprecated');
  const strict = Parser();
  const draft = Parser(options: ParserOptions(allowDirectiveExtensions: true));
  strict.parse(extension).diagnostics.forEach(print);
  print(draft.parse(extension).diagnostics);
}
```

It prints:

```text
GraphQL request:1:9: error GQL006: Document contains more than 4 tokens. Parsing aborted.
GraphQL request:1:9: error GQL010: Document nests deeper than 2 levels.
GraphQL request:1:1: error GQL014: Directive extensions are a working-draft feature; enable them with ParserOptions.allowDirectiveExtensions.
[]
```

## The syntax tree

Every node extends `Node`. A node is immutable and has:

- `start` and `end`, the offsets in the source it was read from (0 for a node
  built in code);
- `children`, in the order of graphql-js's `QueryDocumentKeys`;
- `withChildren(list)`, a copy with other children, which `AstTransformer` uses;
- `isEquivalentTo(other)`, which compares structure and ignores positions.
  Nodes do not override `==`.

The kinds of node are sealed families, so a `switch` over one is checked by the
compiler:

| Family | Members |
|---|---|
| `Definition` (not sealed) | `OperationDefinition`, `FragmentDefinition`, the type-system definitions and extensions |
| `Selection` | `Field`, `FragmentSpread`, `InlineFragment` |
| `Value` | `Variable`, `IntValue`, `FloatValue`, `StringValue`, `BooleanValue`, `NullValue`, `EnumValue`, `ListValue`, `ObjectValue` |
| `TypeRef` | `NamedType`, `ListType`, `NonNullType` |
| `SchemaCoordinate` | `TypeCoordinate`, `MemberCoordinate`, `ArgumentCoordinate`, `DirectiveCoordinate`, `DirectiveArgumentCoordinate` |

`Definition` is not sealed, because the working draft adds definitions: a
`switch` statement over it needs no `default`, and one would hide kinds added
later, so name the cases you handle.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
query Hero(\$id: ID!) {
  hero(id: \$id) { name ...Details }
}

fragment Details on Character { appearsIn }
''');
  final document = const Parser().parse(source).requireDocument();

  for (final definition in document.definitions) {
    switch (definition) {
      case OperationDefinition(:final operation, :final name):
        print('${operation.name} ${name?.value}');
      case FragmentDefinition(:final name, :final typeCondition):
        print('fragment ${name.value} on ${typeCondition.name.value}');
      case _:
        print('another kind of definition');
    }
  }

  // Every node knows where it was read from.
  final operation = document.definitions.first as OperationDefinition;
  final hero = operation.selectionSet.selections.single as Field;
  print(source.body.substring(hero.start, hero.end));
  print(hero.children.length);

  // Structure, without positions.
  final other = const Parser()
      .parse(Source('query Hero(\$id:ID!){hero(id:\$id){name ...Details}}'))
      .requireDocument();
  print(operation.isEquivalentTo(other.definitions.first));
}
```

It prints:

```text
query Hero
fragment Details on Character
hero(id: $id) { name ...Details }
3
true
```

### Single values and types

`parseValue(source, isConst:)` and `parseTypeRef(source)` parse one element and
return a `ParseElementResult`: `ParseElementSuccess(value)` or
`ParseElementFailure`. There is no partial element. With `isConst`, a variable
is an error (`GQL009`), as in a default value.

```dart
import 'package:typed_graphql/typed_graphql.dart';

String describe(TypeRef type) => switch (type) {
  NamedType(:final name) => name.value,
  ListType(:final type) => 'list of ${describe(type)}',
  NonNullType(:final type) => 'non-null (${describe(type)})',
};

void main() {
  const parser = Parser();

  final value = parser.parseValue(Source('[1, {a: "x"}, ENUM]'));
  if (value case ParseElementSuccess(:final value)) {
    print(const Printer(isMinified: true).print(value));
  }

  // A variable is not a constant value.
  final variable = parser.parseValue(Source(r'[$id]'), isConst: true);
  print(variable.diagnostics.single);

  final type = parser.parseTypeRef(Source('[String!]!'));
  if (type case ParseElementSuccess(:final value)) {
    print(describe(value));
  }
}
```

It prints:

```text
[1{a:"x"}ENUM]
GraphQL request:1:2: error GQL009: Unexpected variable "$id" in constant value.
non-null (list of non-null (String))
```

## Printing

`Printer` prints any node, a whole document or a single selection, as GraphQL
text. The default is canonical: character for character what graphql-js's
`print` gives, with lines wrapped at 80 columns. `Printer(isMinified: true)`
drops every character that does not matter, for the wire and for persisted
query hashes: a space only between two tokens that are not punctuators, or
before `...`, and block strings in their shortest form. Parsing the output of either
form gives a tree that `isEquivalentTo` the original.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();
  final source = Source(
    r'query Hero($id:ID!,$withFriends:Boolean=false){hero(id:$id){name '
    r'friends @include(if:$withFriends){name}...on Droid{primaryFunction}}}',
  );
  final document = parser.parse(source).requireDocument();

  print(const Printer().print(document));
  print(const Printer(isMinified: true).print(document));

  final again = parser
      .parse(Source(const Printer(isMinified: true).print(document)))
      .requireDocument();
  print(document.isEquivalentTo(again));

  // Any node prints, not only a document.
  final operation = document.definitions.single as OperationDefinition;
  print(const Printer().print(operation.selectionSet.selections.single));
}
```

It prints:

```text
query Hero($id: ID!, $withFriends: Boolean = false) {
  hero(id: $id) {
    name
    friends @include(if: $withFriends) {
      name
    }
    ... on Droid {
      primaryFunction
    }
  }
}
query Hero($id:ID!$withFriends:Boolean=false){hero(id:$id){name friends@include(if:$withFriends){name}...on Droid{primaryFunction}}}
true
hero(id: $id) {
  name
  friends @include(if: $withFriends) {
    name
  }
  ... on Droid {
    primaryFunction
  }
}
```

Printing recurses over the tree, so it is bounded by the parser's `maxDepth`; a
tree built in code that is deeper can overflow the stack.

## Visiting

`AstWalker().walk(root, visitor)` walks a tree depth-first through `children`
and calls an `AstVisitor` on the way down (`enter`) and on the way up
(`leave`). Both do nothing by default, so a visitor overrides only what it
needs. `enter` returns a `VisitAction`:

- `next` goes into the node's children, and `leave` is called afterwards;
- `skip` passes over the children, and the node is not left either;
- `stop` ends the walk: nothing else is entered or left.

The walker keeps its own stack instead of recursing, so a tree of any depth is
safe on the web too. `ParallelVisitor` runs several visitors in one walk, each
called as if it walked alone, as graphql-js's `visitInParallel` does. It keeps
the skip and stop state of each visitor, so use a new one for every walk.

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Counts the fields of a document, leaving fragment definitions alone.
final class FieldCounter extends AstVisitor {
  int count = 0;

  @override
  VisitAction enter(Node node) => switch (node) {
    FragmentDefinition() => VisitAction.skip,
    Field() => _count(),
    _ => VisitAction.next,
  };

  VisitAction _count() {
    count++;
    return VisitAction.next;
  }
}

/// Collects the names of the variables a document uses.
final class VariableCollector extends AstVisitor {
  final Set<String> names = {};

  @override
  VisitAction enter(Node node) {
    if (node is Variable) names.add(node.name.value);
    return VisitAction.next;
  }
}

/// Stops the walk at the first field with the given name.
final class FieldFinder extends AstVisitor {
  FieldFinder(this.name);

  final String name;
  Field? found;

  @override
  VisitAction enter(Node node) {
    if (node is Field && node.name.value == name) {
      found = node;
      return VisitAction.stop;
    }
    return VisitAction.next;
  }
}

void main() {
  final source = Source(r'''
query Hero($id: ID!) { hero(id: $id) { name ...Details } }
fragment Details on Character { appearsIn friends { name } }
''');
  final document = const Parser().parse(source).requireDocument();
  const walker = AstWalker();

  final counter = FieldCounter();
  walker.walk(document, counter);
  print('fields outside fragments: ${counter.count}');

  // Two visitors, one walk.
  final other = FieldCounter();
  final variables = VariableCollector();
  walker.walk(document, ParallelVisitor([other, variables]));
  print('${other.count} fields, variables ${variables.names}');

  final finder = FieldFinder('friends');
  walker.walk(document, finder);
  if (finder.found case final field?) {
    print('friends at ${source.locationOf(field.start)}');
  }
}
```

It prints:

```text
fields outside fragments: 2
2 fields, variables {id}
friends at 2:43
```

## Transforming

`AstTransformer.transform(root)` rebuilds a tree bottom-up. `rewrite(node)`
sees each node after its children were rewritten and returns what takes its
place: the node itself to keep it, another node to replace it, or `null` to
remove it from its parent. The parent is rebuilt with `withChildren`, so it
decides what it accepts: removing a child it requires, such as the name of a
`Field`, is a `StateError`.

The original tree is never changed, and a branch where nothing changed keeps
its instance, so `identical` tells whether a transform changed anything. Like
the walker, it keeps its own stack instead of recursing.

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Adds `__typename` to every selection set that lacks it.
final class AddTypename extends AstTransformer {
  const AddTypename();

  @override
  Node? rewrite(Node node) => switch (node) {
    SelectionSet(:final selections) when !selections.any(_isTypename) =>
      SelectionSet([...selections, Field(null, const Name('__typename'))]),
    _ => node,
  };

  static bool _isTypename(Selection selection) =>
      selection is Field && selection.name.value == '__typename';
}

/// Removes the directives with the given name wherever they are applied.
final class StripDirective extends AstTransformer {
  const StripDirective(this.name);

  final String name;

  @override
  Node? rewrite(Node node) =>
      node is Directive && node.name.value == name ? null : node;
}

/// Tries to remove the name of the field `hero`, which a field requires.
final class RemoveHeroName extends AstTransformer {
  const RemoveHeroName();

  @override
  Node? rewrite(Node node) =>
      node is Name && node.value == 'hero' ? null : node;
}

void main() {
  const printer = Printer(isMinified: true);
  final document = const Parser()
      .parse(Source('query Q @client { hero @client { name } }'))
      .requireDocument();

  print(printer.print(const AddTypename().transform(document)!));
  print(printer.print(const StripDirective('client').transform(document)!));

  // The original is untouched, and an unchanged tree is the same instance.
  print(printer.print(document));
  print(identical(const StripDirective('other').transform(document), document));

  try {
    const RemoveHeroName().transform(document);
  } on StateError {
    print('a field needs its name');
  }
}
```

It prints:

```text
query Q@client{hero@client{name __typename}__typename}
query Q{hero{name}}
query Q@client{hero@client{name}}
true
a field needs its name
```

## Schema coordinates

A schema coordinate names one element of a schema in a single line, such as
`Query.hero(episode:)` (September2025, "Schema Coordinates").
`Parser().parseSchemaCoordinate(source)` returns a
`ParseElementResult<SchemaCoordinate>`. A coordinate holds no ignored tokens, so
white space is an error. `ParserOptions` do not apply to it.

| Text | Node |
|---|---|
| `Query` | `TypeCoordinate` |
| `Query.hero` | `MemberCoordinate`: a field, input field or enum value |
| `Query.hero(episode:)` | `ArgumentCoordinate` |
| `@skip` | `DirectiveCoordinate` |
| `@skip(if:)` | `DirectiveArgumentCoordinate` |

```dart
import 'package:typed_graphql/typed_graphql.dart';

String describe(SchemaCoordinate coordinate) => switch (coordinate) {
  TypeCoordinate(:final name) => 'the type ${name.value}',
  MemberCoordinate(:final name, :final memberName) =>
    'the member ${memberName.value} of ${name.value}',
  ArgumentCoordinate(:final name, :final fieldName, :final argumentName) =>
    'the argument ${argumentName.value} of ${name.value}.${fieldName.value}',
  DirectiveCoordinate(:final name) => 'the directive @${name.value}',
  DirectiveArgumentCoordinate(:final name, :final argumentName) =>
    'the argument ${argumentName.value} of @${name.value}',
};

void main() {
  const parser = Parser();
  const texts = ['Query', 'Query.hero', 'Query.hero(episode:)', '@skip(if:)'];
  for (final text in texts) {
    final result = parser.parseSchemaCoordinate(Source(text));
    if (result case ParseElementSuccess(:final value)) {
      print('$text is ${describe(value)}');
    }
  }

  final spaced = parser.parseSchemaCoordinate(Source('Query. hero'));
  print(spaced.diagnostics.single);
}
```

It prints:

```text
Query is the type Query
Query.hero is the member hero of Query
Query.hero(episode:) is the argument episode of Query.hero
@skip(if:) is the argument if of @skip
GraphQL request:1:7: error GQL001: Invalid character: " ".
```

## Tokens

`Lexer(source, sink).advance()` returns the next `Token`: a `TokenKind`, the
`start` and `end` offsets and, for names, numbers and strings, the `value`.
Ignored tokens (white space, commas, comments) are skipped; `keepComments`
returns the comments too. The lexer never throws: text that is no token becomes
one `TokenKind.error` token over the offending run and one diagnostic in the
sink. `maxTokens` stops it with `GQL006`. The parser reads tokens through this
class, so you need it only for tooling that works on tokens.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final lexer = Lexer(Source('{ hero(id: 1) } # done'), DiagnosticSink());
  for (
    var token = lexer.advance();
    token.kind != TokenKind.eof;
    token = lexer.advance()
  ) {
    print(token);
  }
}
```

It prints:

```text
"{"@0:1
Name "hero"@2:6
"("@6:7
Name "id"@7:9
":"@9:10
Int "1"@11:12
")"@12:13
"}"@14:15
```
````

- [ ] **Step 2: Run the guide tests**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/doc_snippets_test.dart test/doc/doc_links_test.dart )`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add packages/typed_graphql/doc/language.md
git commit -m "docs(typed_graphql): add the Language guide

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Task 6: The Schema guide

**Files:**
- Create: `packages/typed_graphql/doc/schema.md`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: the guide "Schema" (category `schema`). Its sections, in order: Building a schema from SDL; Reading a schema; Built-ins; Problems in the SDL; Extending a schema; Printing a schema; What building does not check. The last section is the named place that M3b extends (see "How M3b extends these guides"): it says, with a program, that references to missing types and roots of the wrong kind build without a diagnostic.

- [ ] **Step 1: Write the guide**

Create `packages/typed_graphql/doc/schema.md`:

````markdown
# Schema

The schema layer turns SDL into an immutable `Schema`, extends it, and prints it
back. A schema is plain data: named types, directive definitions and the names
of the root types. It has no behaviour; the codecs of its scalars are held
apart (see the Scalars & Codecs topic).

## Building a schema from SDL

Parse the SDL with the language layer, then build:
`SchemaBuilder().fromSdl(document, source:)` returns a sealed `BuildResult`:

- `BuildSuccess(schema)` when the SDL has no construction problem.
- `BuildFailure(partial, diagnostics)` when it has. `partial` is everything that
  could be built; what an error is about is left out. `diagnostics` holds every
  problem, `GQL1xx` codes with the place in the document, ordered by position.

`source` is the text the document was parsed from. It gives every element and
every diagnostic its span; without it the spans are null. The built-in scalars,
directives and introspection types are in every schema without being declared
(see Built-ins below). Extensions (`extend type`, `extend schema`, ...) in the
document are applied while building.

```dart
import 'package:typed_graphql/typed_graphql.dart';

const sdl = '''
"A character of the saga."
interface Character {
  id: ID!
  name: String!
}

type Human implements Character {
  id: ID!
  name: String!
  homePlanet: String @deprecated(reason: "Use origin.")
}

type Droid implements Character {
  id: ID!
  name: String!
  primaryFunction: String
}

union SearchResult = Human | Droid

enum Episode {
  NEWHOPE
  EMPIRE
  JEDI
}

type Query {
  hero(episode: Episode = JEDI): Character
  search(text: String!): [SearchResult!]!
}
''';

void main() {
  final source = Source(sdl, name: 'schema.graphql');
  final document = const Parser().parse(source).requireDocument();
  final result = const SchemaBuilder().fromSdl(document, source: source);
  if (result case BuildSuccess(:final schema)) {
    print('query root: ${schema.queryTypeName}');
    print('mutation root: ${schema.mutationTypeName}');
    for (final type in schema.types) {
      print('${type.name}: ${describe(type)}');
    }
  }
}

String describe(SchemaType type) => switch (type) {
  ScalarType() => 'scalar',
  ObjectType(:final fields) => 'object with ${fields.length} fields',
  InterfaceType(:final fields) => 'interface with ${fields.length} fields',
  UnionType(:final memberTypes) => 'union of ${memberTypes.length}',
  EnumType(:final values) => 'enum of ${values.length}',
  InputObjectType(:final fields) => 'input object with ${fields.length}',
};
```

It prints:

```text
query root: Query
mutation root: null
Character: interface with 2 fields
Human: object with 3 fields
Droid: object with 3 fields
SearchResult: union of 2
Episode: enum of 3
Query: object with 2 fields
```

`SchemaBuilder(includesDeferAndStream: true)` adds `@defer` and `@stream`, which
graphql-js defines and the specification does not yet.

## Reading a schema

`Schema` lists what was declared, in declaration order: `types`, `directives`,
and the names of the roots (`queryTypeName`, `mutationTypeName`,
`subscriptionTypeName`; `rootTypeName(operation)` picks one by `OperationType`).
`typeNamed(name)` and `directiveNamed(name)` find an element, the built-ins
included, or return null.

The elements of the model:

| Class | Is |
|---|---|
| `SchemaType` | The sealed family of named types: `ScalarType`, `ObjectType`, `InterfaceType`, `UnionType`, `EnumType`, `InputObjectType` |
| `SchemaField` | A field of an object or interface: `name`, `type`, `arguments`, `description` |
| `InputValue` | An argument or an input field, with its `defaultValue` |
| `SchemaEnumValue` | A value of an enum |
| `SchemaDirective` | A directive definition: `arguments`, `isRepeatable`, `locations` |
| `AppliedDirective` | A directive applied to an element, with its arguments as written |

The spec's own names, `FieldDefinition`, `EnumValueDefinition` and
`DirectiveDefinition`, already name syntax tree nodes, so the schema's elements
take a `Schema` prefix.

Types are references by name: a field's `type` is a language `TypeRef`
(`NamedType`, `ListType`, `NonNullType`), and `typeNamed` resolves it. A cyclic
schema therefore needs no special handling. Default values and the arguments of
applied directives are constant `Value` nodes, which `Printer` prints. Every
element has a `span`, and `deprecationReason`, `specifiedByUrl` and `isOneOf`
read the applied directives for you.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
enum Episode { NEWHOPE EMPIRE JEDI }

type Human {
  name: String!
  homePlanet: String @deprecated(reason: "Use origin.")
}

type Query {
  "The hero of an episode."
  hero(episode: Episode = JEDI, limit: Int): Human
}
''');
  final document = const Parser().parse(source).requireDocument();
  final schema = switch (const SchemaBuilder().fromSdl(document)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };
  const printer = Printer();

  final query = schema.typeNamed(schema.queryTypeName!) as ObjectType;
  final hero = query.fieldNamed('hero')!;
  print('${hero.name}: ${printer.print(hero.type)} (${hero.description})');
  for (final argument in hero.arguments) {
    final defaultValue = argument.defaultValue;
    print(
      '  ${argument.name}: ${printer.print(argument.type)}'
      '${defaultValue == null ? '' : ' = ${printer.print(defaultValue)}'}',
    );
  }

  // A reference is a name: resolve it with typeNamed.
  if (hero.type case NamedType(:final name)) {
    print(schema.typeNamed(name.value)?.name);
  }

  final human = schema.typeNamed('Human') as ObjectType;
  print(human.fieldNamed('homePlanet')?.deprecationReason);
  print(human.fieldNamed('name')?.deprecationReason);
  print(schema.typeNamed('Droid'));
}
```

It prints:

```text
hero: Human (The hero of an episode.)
  episode: Episode = JEDI
  limit: Int
Human
Use origin.
null
null
```

## Built-ins

Every schema has the five built-in scalars (`String`, `Int`, `Float`, `Boolean`,
`ID`), the five specified directives (`@include`, `@skip`, `@deprecated`,
`@specifiedBy`, `@oneOf`) and the introspection types (`__Schema`, `__Type`, ...)
without declaring them. `Schema.types` lists only what was declared; `typeNamed`
and `directiveNamed` fall back to `BuiltIns`, which reads their definitions once
from the Appendix of the specification. They have no spans. A document cannot
redefine or extend them (`GQL103`).

`@defer` and `@stream` exist only in a schema built with
`includesDeferAndStream`.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final schema = Schema();

  // Nothing was declared, yet the built-ins are there.
  print(schema.types.length);
  print(schema.typeNamed('String')?.name);
  print(schema.typeNamed('__Schema')?.name);
  final deprecated = schema.directiveNamed('deprecated');
  print(deprecated?.arguments.map((argument) => argument.name).toList());
  print(deprecated?.locations);

  // @defer and @stream are opt-in.
  print(schema.directiveNamed('defer'));
  print(Schema(includesDeferAndStream: true).directiveNamed('defer')?.name);

  print(const BuiltIns().scalars.map((scalar) => scalar.name).toList());
  print(const BuiltIns().directives.map((d) => d.name).toList());
}
```

It prints:

```text
0
String
__Schema
[reason]
[FIELD_DEFINITION, ARGUMENT_DEFINITION, INPUT_FIELD_DEFINITION, ENUM_VALUE]
null
defer
[String, Int, Float, Boolean, ID]
[include, skip, deprecated, specifiedBy, oneOf]
```

## Problems in the SDL

A construction problem is a diagnostic, and the build goes on without the
offending part: the first definition of a name wins, a repeated member is
dropped, an extension of a missing type is ignored. A repeat points at its own
name and relates to the definition it repeats. The messages are graphql-js's
SDL-rule messages.

| Code | Reported for |
|---|---|
| `GQL100` | an operation or fragment in the document |
| `GQL101`, `GQL102` | a repeated type or directive name |
| `GQL103` | a definition or extension of a built-in |
| `GQL104`, `GQL105`, `GQL106` | a repeated field, argument or enum value |
| `GQL107`, `GQL108` | a second schema definition, a second root of one operation |
| `GQL109`, `GQL110` | an extension of a missing type, or of a type of another kind |

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
type Query { a: Int }
type Query { b: Int }
extend type Missing { x: Int }
type Other { y: Int }
''', name: 'broken.graphql');
  final document = const Parser().parse(source).requireDocument();

  switch (const SchemaBuilder().fromSdl(document, source: source)) {
    case BuildSuccess():
      print('built');
    case BuildFailure(:final partial, :final diagnostics):
      diagnostics.forEach(print);
      final query = partial.typeNamed('Query') as ObjectType;
      print('Query keeps ${query.fields.map((field) => field.name)}');
      print(partial.types.map((type) => type.name));
  }
}
```

It prints:

```text
broken.graphql:2:6: error GQL101: There can be only one type named "Query".
broken.graphql:3:13: error GQL109: Cannot extend type "Missing" because it is not defined.
Query keeps (a)
(Query, Other)
```

## Extending a schema

Extensions in the same document are applied while building. To extend a schema
that already exists, call `SchemaBuilder().extend(schema, document, source:)`,
graphql-js's `extendSchema`: it applies the definitions and extensions of a
document to a schema and returns a new one, or the same schema when the document
has none. The original is not changed. An extension appends its members,
interfaces, union members and directives after the type's own, in document
order, and the type keeps the span of its definition. A member the schema
already has is an error (`GQL104`).

```dart
import 'package:typed_graphql/typed_graphql.dart';

Schema build(String text) {
  final source = Source(text);
  final document = const Parser().parse(source).requireDocument();
  return switch (const SchemaBuilder().fromSdl(document, source: source)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };
}

void main() {
  final base = build('''
type Query { hero: String }
extend type Query { villain: String }
''');
  final query = base.typeNamed('Query') as ObjectType;
  print(query.fields.map((field) => field.name).toList());

  // A later document extends a schema that already exists.
  final source = Source('''
extend type Query { sidekick: String }
enum Side { LIGHT DARK }
''', name: 'more.graphql');
  final document = const Parser().parse(source).requireDocument();
  final result = const SchemaBuilder().extend(base, document, source: source);
  if (result case BuildSuccess(:final schema)) {
    final extended = schema.typeNamed('Query') as ObjectType;
    print(extended.fields.map((field) => field.name).toList());
    print(schema.types.map((type) => type.name).toList());
  }
  print((base.typeNamed('Query') as ObjectType).fields.length);

  // A member the schema already has is an error.
  final repeated = Source(
    'extend type Query { hero: Int }',
    name: 'dup.graphql',
  );
  const SchemaBuilder()
      .extend(
        base,
        const Parser().parse(repeated).requireDocument(),
        source: repeated,
      )
      .diagnostics
      .forEach(print);
}
```

It prints:

```text
[hero, villain]
[hero, villain, sidekick]
[Query, Side]
2
dup.graphql:1:21: error GQL104: Field "Query.hero" already exists in the schema. It cannot also be defined in this type extension.
```

## Printing a schema

`SchemaPrinter().print(schema)` prints a schema as SDL, laid out as graphql-js's
`printSchema`: the schema definition when it says more than the default root
names (a description, directives, a root with another name, or a type named
`Query`, `Mutation` or `Subscription` that is not a root), then the directive
definitions and the types, in declaration order, separated by a blank line. Unlike graphql-js, it
prints every applied directive as written, so SDL to schema to SDL loses
nothing. `SchemaPrinter(includesBuiltIns: true)` prints the built-in directives,
scalars and introspection types too.

An empty schema prints an empty string, which does not parse: an empty document
is a syntax error.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
"The saga."
schema { query: Root }

directive @cost(units: Int = 1) on FIELD_DEFINITION

type Root {
  hero(episode: Episode = JEDI): String @cost(units: 2)
}

enum Episode {
  NEWHOPE
  JEDI @deprecated(reason: "Retired.")
}
''');
  final document = const Parser().parse(source).requireDocument();
  final schema = switch (const SchemaBuilder().fromSdl(document)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };

  final text = const SchemaPrinter().print(schema);
  print(text);

  // The printed SDL builds the same schema again.
  final again = const Parser().parse(Source(text)).requireDocument();
  if (const SchemaBuilder().fromSdl(again) case BuildSuccess(schema: final s)) {
    print(const SchemaPrinter().print(s) == text);
  }

  // The built-ins are printed only when asked for.
  final full = const SchemaPrinter(includesBuiltIns: true).print(schema);
  print(text.contains('directive @include'));
  print(full.contains('directive @include'));
}
```

It prints:

```text
"""The saga."""
schema {
  query: Root
}

directive @cost(units: Int = 1) on FIELD_DEFINITION

type Root {
  hero(episode: Episode = JEDI): String @cost(units: 2)
}

enum Episode {
  NEWHOPE
  JEDI @deprecated(reason: "Retired.")
}
true
false
true
```

## What building does not check

Building a schema does not validate it. A field may name a type that does not
exist, a root may name a type of the wrong kind, and an object may claim to
implement an interface without its fields; the builder keeps them all as
written. The build reports only what it cannot represent: the problems above.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
type Query { hero: Unknown }
schema { mutation: Query }
''');
  final document = const Parser().parse(source).requireDocument();
  final result = const SchemaBuilder().fromSdl(document);

  // It builds: nothing here is a construction problem.
  print(result is BuildSuccess);
  if (result case BuildSuccess(:final schema)) {
    print(schema.typeNamed('Unknown'));
    print(schema.mutationTypeName);
  }
}
```

It prints:

```text
true
null
Query
```

Checking a schema against the rules of the specification arrives in a later
release of this package.
````

- [ ] **Step 2: Run the guide tests**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/doc_snippets_test.dart test/doc/doc_links_test.dart )`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add packages/typed_graphql/doc/schema.md
git commit -m "docs(typed_graphql): add the Schema guide

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Task 7: The Scalars and Codecs guide

**Files:**
- Create: `packages/typed_graphql/doc/scalars.md`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: the guide "Scalars & Codecs" (category `scalars`, the types of `lib/src/schema/scalars/`). It states: the `ScalarCodec<T>` contract (`decode` never throws, `encode` throws `ArgumentError`), the five built-in codecs and their messages, `ScalarCodecs.withCodec` (immutable, built-ins cannot be replaced, `codecFor`), a custom `DateTime` codec, `LiteralConverter`.

- [ ] **Step 1: Write the guide**

Create `packages/typed_graphql/doc/scalars.md`:

````markdown
# Scalars and codecs

A schema says that a scalar called `DateTime` exists. It does not say how a
`DateTime` travels as JSON or what Dart type holds it; that is the job of a
codec. This package keeps the two apart: `ScalarType` is plain schema data and
has no behaviour, so one schema can serve a server, a client and a code
generator, each with the codecs it needs.

## The codec contract

`ScalarCodec<T>` has two methods:

- `decode(JsonValue)` reads input: a variable, a result value or a literal
  converted to JSON. It returns a `DecodeResult<T>`: a `DecodeSuccess` with the
  value, or a `DecodeFailure` that says why the value cannot be represented.
  It never throws.
- `encode(T)` writes a value as JSON. A value the type cannot hold can only come
  from code, so `encode` throws an `ArgumentError` for it.

The five built-in scalars have codecs, with graphql-js's error messages:

| Scalar | Codec | Dart type |
|---|---|---|
| `Int` | `IntCodec` | `int`, a signed 32-bit integer |
| `Float` | `FloatCodec` | `double` |
| `String` | `StringCodec` | `String` |
| `Boolean` | `BooleanCodec` | `bool` |
| `ID` | `IdCodec` | `String`; an integer input becomes its decimal text |

```dart
import 'package:typed_graphql/typed_graphql.dart';

String show<T>(DecodeResult<T> result) => switch (result) {
  DecodeSuccess(:final value) => 'ok: $value',
  DecodeFailure(:final message) => 'failed: $message',
};

void main() {
  const int32 = IntCodec();
  print(show(int32.decode(JsonNumber(42))));
  print(show(int32.decode(JsonNumber(3.0))));
  print(show(int32.decode(JsonNumber(1.5))));
  print(show(int32.decode(JsonNumber(4294967296))));
  print(show(int32.decode(const JsonString('42'))));

  // An ID accepts a string or an integer, and always gives a string.
  print(show(const IdCodec().decode(JsonNumber(7))));

  print(const BooleanCodec().encode(true));
  try {
    int32.encode(4294967296);
  } on ArgumentError catch (error) {
    print(error.message);
  }
}
```

It prints:

```text
ok: 42
ok: 3
failed: Int cannot represent non-integer value: 1.5
failed: Int cannot represent non 32-bit signed integer value: 4294967296
failed: Int cannot represent non-integer value: "42"
ok: 7
true
is not a 32-bit integer
```

## Registering codecs

`ScalarCodecs` maps scalar names to codecs. `const ScalarCodecs()` holds the
five built-ins. `withCodec(name, codec)` returns a new registry with one more
codec and leaves the first one alone, so a registry is safe to share. The
built-ins cannot be replaced: naming one is an `ArgumentError`, because the
specification fixes what they mean. `codecFor(name)` finds a codec or returns
null; the server and the client call it for every scalar they meet.

## A custom scalar

Write the codec for the Dart type you want, say a `DateTime` kept as an ISO 8601
string, and register it under the scalar's name.

```dart
import 'package:typed_graphql/typed_graphql.dart';

final class DateTimeCodec implements ScalarCodec<DateTime> {
  const DateTimeCodec();

  @override
  DecodeResult<DateTime> decode(JsonValue json) {
    if (json case JsonString(:final value)) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return DecodeSuccess(parsed.toUtc());
      }
    }
    return DecodeFailure('DateTime cannot represent value: $json');
  }

  @override
  JsonValue encode(DateTime value) =>
      JsonString(value.toUtc().toIso8601String());
}

void main() {
  final codecs = const ScalarCodecs().withCodec(
    'DateTime',
    const DateTimeCodec(),
  );

  // The original registry is unchanged.
  print(const ScalarCodecs().codecFor('DateTime'));
  final codec = codecs.codecFor('DateTime')! as ScalarCodec<DateTime>;

  final moment = DateTime.utc(2026, 10, 14, 9, 30);
  print(codec.encode(moment));
  print(codec.decode(const JsonString('2026-10-14T09:30:00Z')));
  print(codec.decode(JsonNumber(1)));

  try {
    codecs.withCodec('Int', const DateTimeCodec());
  } on ArgumentError catch (error) {
    print(error.message);
  }
}
```

It prints:

```text
null
"2026-10-14T09:30:00.000Z"
DecodeSuccess(2026-10-14 09:30:00.000Z)
$: DateTime cannot represent value: 1
is a built-in scalar
```

The registry holds codecs as `ScalarCodec<Object>`, so a lookup returns the
codec without its type argument; cast it to the Dart type you registered, as
above. The typed server and the generated client do this for you.

## Literals

Input can also be a literal written in a document, such as a default value or an
argument. A literal is a language `Value` node, and a codec decodes `JsonValue`.
`LiteralConverter().convert(value)` bridges the two, so a codec has one entry
point and no `parseLiteral`: an enum value becomes its name as a string, a list
and an object convert element by element, and a variable has no value at this
point and fails.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const converter = LiteralConverter();
  final source = Source('{ f(a: 12, b: JEDI, c: [1, "two"], d: {x: true}) }');
  final document = const Parser().parse(source).requireDocument();
  final field = document.definitions.single as OperationDefinition;
  final selection = field.selectionSet.selections.single as Field;

  for (final argument in selection.arguments) {
    print('${argument.name.value}: ${converter.convert(argument.value)}');
  }

  // A literal that converts is then read by the scalar's codec.
  final converted = converter.convert(selection.arguments.first.value);
  if (converted case DecodeSuccess(:final value)) {
    print(const IntCodec().decode(value));
  }
}
```

It prints:

```text
a: DecodeSuccess(12)
b: DecodeSuccess("JEDI")
c: DecodeSuccess([1,"two"])
d: DecodeSuccess({"x":true})
DecodeSuccess(12)
```
````

- [ ] **Step 2: Run the guide tests**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/doc_snippets_test.dart test/doc/doc_links_test.dart )`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add packages/typed_graphql/doc/scalars.md
git commit -m "docs(typed_graphql): add the Scalars and Codecs guide

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Task 8: dartdoc categories, tags and the zero-warnings check

**Files:**
- Create: `packages/typed_graphql/dartdoc_options.yaml`
- Create: `packages/typed_graphql/test/doc/public_type.dart`, `public_type_test.dart`, `category_tags_test.dart`
- Modify: the doc comment of every exported public type in `packages/typed_graphql/lib/src/**` (73 files, 137 tags) and `packages/typed_graphql/lib/typed_graphql.dart`, by a script
- Modify: `.github/workflows/ci.yml`, `.gitignore`

**Interfaces:**
- Consumes: the six guides of Tasks 1 and 3 to 7 (the options file points at them).
- Produces: category `<name>` for each exported type = the folder of its file under `lib/src/` (`diagnostics`, `language`, `protocol`, `schema`), except `lib/src/schema/scalars/` which is `scalars`; the library page is `getting-started`. `PublicTypes().declaredIn(String source) -> List<PublicType(name, line, documentation)>`. Rule for later stages: a new exported type carries `/// {@category <folder>}` in its doc comment, and a new folder under `lib/src/` that is exported needs its category, guide and order entry (this is how M3b and M4 are forced to document their types).

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/doc/public_type_test.dart`:

````dart
import 'package:test/test.dart';

import 'public_type.dart';

void main() {
  const types = PublicTypes();

  test('finds classes of every modifier, enums, mixins and typedefs', () {
    final found = types.declaredIn('''
abstract interface class A {}
sealed class B {}
final class const C() {}
enum D { x }
mixin E {}
typedef F = int;
extension type G(int value) {}
''');
    expect(found.map((type) => type.name), ['A', 'B', 'C', 'D', 'E', 'F', 'G']);
  });

  test('skips private types', () {
    expect(
      types.declaredIn('class _Hidden {}\nclass Shown {}\n').single.name,
      'Shown',
    );
  });

  test('collects the doc comment, through annotations', () {
    final type = types
        .declaredIn(
          '/// First line.\n/// {@category schema}\n@immutable\nclass X {}\n',
        )
        .single;
    expect(type.documentation, ['First line.', '{@category schema}']);
    expect(type.line, 4);
  });

  test('a doc comment does not leak to the next declaration', () {
    final found = types.declaredIn('/// Doc.\nclass A {}\nclass B {}\n');
    expect(found.last.documentation, isEmpty);
  });
}
````

Create `packages/typed_graphql/test/doc/category_tags_test.dart`. It parses the barrel's exports, checks the tag of each exported type against the folder of its file, and checks the options file (its categories are exactly the ones used, each has an existing guide, the order lists each once):

````dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'public_type.dart';

/// Every exported type is in the dartdoc category of its folder, and
/// `dartdoc_options.yaml` declares those categories, each with a guide
/// (R11.2).
void main() {
  final barrel = File('lib/typed_graphql.dart').readAsStringSync();
  final exported = [
    for (final match in RegExp("export '([^']+)';").allMatches(barrel))
      match[1]!,
  ];
  final options = File('dartdoc_options.yaml').readAsStringSync();
  final declared = [
    for (final match in RegExp(
      r'^ {4}([a-z-]+):$',
      multiLine: true,
    ).allMatches(options))
      match[1]!,
  ];

  /// The category of the types in the library file [path], from `lib/`.
  String categoryOf(String path) => switch (path.split('/')) {
    ['src', 'schema', 'scalars', ...] => 'scalars',
    ['src', final layer, ...] => layer,
    _ => throw ArgumentError.value(path, 'path', 'is not under lib/src'),
  };

  test('the library page is in the getting-started category', () {
    expect(barrel, contains('/// {@category getting-started}\nlibrary;'));
  });

  test('every category used is declared, and every one declared is used', () {
    final used = {'getting-started', ...exported.map(categoryOf)};
    expect(declared.toSet(), used);
  });

  test('every declared category has its guide', () {
    for (final match in RegExp(r'markdown: (doc/\S+)').allMatches(options)) {
      expect(File(match[1]!).existsSync(), isTrue, reason: match[1]);
    }
    expect(
      RegExp('markdown: doc').allMatches(options),
      hasLength(declared.length),
    );
  });

  test('the category order lists every declared category once', () {
    final order = [
      for (final match in RegExp(
        r'^ {4}- ([a-z-]+)$',
        multiLine: true,
      ).allMatches(options))
        match[1]!,
    ];
    expect(order, declared);
  });

  group('exported types', () {
    for (final path in exported) {
      test(path, () {
        final tag = '{@category ${categoryOf(path)}}';
        final source = File('lib/$path').readAsStringSync();
        final untagged = [
          for (final type in const PublicTypes().declaredIn(source))
            if (!type.documentation.contains(tag)) type.name,
        ];
        expect(untagged, isEmpty, reason: 'add $tag to their doc comments');
      });
    }
  });
}
````

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/public_type_test.dart test/doc/category_tags_test.dart )`
Expected: FAIL to load, `Target of URI doesn't exist: 'public_type.dart'`.

- [ ] **Step 2: Write the type finder**

Create `packages/typed_graphql/test/doc/public_type.dart`:

````dart
/// A public type declared in a Dart file, with its doc comment.
final class PublicType(
  /// The type's name.
  final String name,

  /// The 1-based line of the declaration.
  final int line,

  /// The doc comment, one string per line, without the `///`.
  final List<String> documentation,
) {
  /// Creates a description.
  this;
}

/// Finds the public classes, enums, mixins and typedefs of Dart source.
///
/// The code rules give a library file its types at the top level and a
/// declaration on one line, so a line scan is enough; a type whose name
/// starts with `_` is private and skipped.
final class PublicTypes {
  /// Creates the finder.
  const PublicTypes();

  static final RegExp _declaration = RegExp(
    r'^(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*'
    r'(?:class|enum|mixin|typedef|extension type)\s+(?:const\s+)?([A-Z]\w*)',
  );

  /// The public types declared in [source], in order.
  List<PublicType> declaredIn(String source) {
    final types = <PublicType>[];
    var documentation = <String>[];
    for (final (index, line) in source.split('\n').indexed) {
      if (line.startsWith('///')) {
        documentation.add(line.substring(3).trim());
      } else if (!line.startsWith('@')) {
        if (_declaration.firstMatch(line) case final match?) {
          types.add(PublicType(match[1]!, index + 1, documentation));
        }
        documentation = [];
      }
    }
    return types;
  }
}
````

Run the same command.
Expected: `public_type_test.dart` PASSES (4 tests); `category_tags_test.dart` FAILS: `FileSystemException ... dartdoc_options.yaml` and `Expected: ... add {@category schema} to their doc comments` for each exported file.

- [ ] **Step 3: Write the options file**

Create `packages/typed_graphql/dartdoc_options.yaml`:

````yaml
dartdoc:
  categories:
    getting-started:
      markdown: doc/getting_started.md
      displayName: Getting Started
    diagnostics:
      markdown: doc/diagnostics.md
      displayName: Diagnostics
    language:
      markdown: doc/language.md
      displayName: Language
    protocol:
      markdown: doc/protocol.md
      displayName: Wire Protocol
    schema:
      markdown: doc/schema.md
      displayName: Schema
    scalars:
      markdown: doc/scalars.md
      displayName: Scalars & Codecs
  categoryOrder:
    - getting-started
    - diagnostics
    - language
    - protocol
    - schema
    - scalars
  showUndocumentedCategories: true
````

Run the same command again.
Expected: the options tests pass; `exported types` tests still FAIL, listing the untagged types of each file.

- [ ] **Step 4: Tag the types with a script**

The tags are 137 one-line additions, so a script writes them. It is not committed: it has a top-level function, which the code rules forbid in the repository. Save it as `/tmp/tag_categories.dart` (any path outside the repository):

````dart
// One-off: adds `{@category <name>}` to the doc comment of every public type
// the barrel exports. Run from packages/typed_graphql. Idempotent.
import 'dart:io';

final RegExp _declaration = RegExp(
  r'^(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*'
  r'(?:class|enum|mixin|typedef|extension type)\s+(?:const\s+)?([A-Z]\w*)',
);

String categoryOf(String path) => switch (path.split('/')) {
  ['src', 'schema', 'scalars', ...] => 'scalars',
  ['src', final layer, ...] => layer,
  _ => throw ArgumentError.value(path, 'path', 'is not under lib/src'),
};

void main() {
  final barrel = File('lib/typed_graphql.dart');
  final text = barrel.readAsStringSync();
  const tag = '/// {@category getting-started}\nlibrary;';
  if (!text.contains(tag)) {
    barrel.writeAsStringSync(
      text.replaceFirst('\nlibrary;', '\n///\n/// {@category getting-started}\nlibrary;'),
    );
  }
  var changed = 0;
  for (final match in RegExp(r"export '([^']+)';").allMatches(text)) {
    final path = match[1]!;
    final file = File('lib/$path');
    final lines = file.readAsStringSync().split('\n');
    final category = '/// {@category ${categoryOf(path)}}';
    // From the bottom up, so insertions do not move the lines to come.
    for (var i = lines.length - 1; i >= 0; i--) {
      if (!_declaration.hasMatch(lines[i])) continue;
      var docEnd = i - 1;
      while (docEnd >= 0 && lines[docEnd].startsWith('@')) {
        docEnd--;
      }
      if (docEnd < 0 || !lines[docEnd].startsWith('///')) {
        throw StateError('$path:${i + 1}: no doc comment');
      }
      var docStart = docEnd;
      while (docStart > 0 && lines[docStart - 1].startsWith('///')) {
        docStart--;
      }
      if (lines.sublist(docStart, docEnd + 1).contains(category)) continue;
      lines.insertAll(docEnd + 1, ['///', category]);
      changed++;
    }
    file.writeAsStringSync(lines.join('\n'));
  }
  print('tagged $changed types');
}
````

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 120 dart /tmp/tag_categories.dart )`
Expected: `tagged 136 types`. Running it again prints `tagged 0 types` (it is idempotent). Each tagged doc comment now ends with a blank `///` line and `/// {@category <name>}`; `lib/typed_graphql.dart` gets `/// {@category getting-started}` before `library;`.

Check that only comments changed: `git diff --stat -- packages/typed_graphql/lib` shows 73 files, and `git diff -U0 -- packages/typed_graphql/lib | grep '^[+-]' | grep -v '^+++\|^---' | grep -v '{@category\|^+///$'` prints nothing.

- [ ] **Step 5: Run the category tests**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/category_tags_test.dart )`
Expected: PASS (one test per exported file, plus four).

Prove it can fail: delete one `/// {@category language}` line in `lib/src/language/printer/printer.dart`, expect FAIL naming `Printer`, and put the line back.

- [ ] **Step 6: Generate the reference and read the summary**

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart doc )`
Expected: one `Generating docs for category ...` line per category (Getting Started, Diagnostics, Language, Wire Protocol, Schema, Scalars & Codecs), then `Found 0 warnings and 0 errors.` Open `doc/api/index.html` once if a browser is at hand: the sidebar groups the types by topic and each topic page shows its guide. Then remove the output: `rm -rf doc/api`.

`dart doc` exits 0 even with warnings, so CI must read the summary line.

- [ ] **Step 7: Add the CI step and the ignore rule**

In `.github/workflows/ci.yml`, in the `analyze` job, after the `Analyze` step, add:

```yaml
      # `dart doc` exits 0 even with warnings, so the summary line is read.
      - name: API reference has no warnings
        shell: bash
        working-directory: packages/typed_graphql
        run: dart doc 2>&1 | tee "$RUNNER_TEMP/doc.log" && grep -q "Found 0 warnings and 0 errors" "$RUNNER_TEMP/doc.log"
```

In `.gitignore`, before the `# Avoid committing pubspec.lock` comment, add:

```text
# Output of `dart doc`.
doc/api/

```

- [ ] **Step 8: Format, analyze, test, commit**

From the root, each wrapped in `( ulimit -v 8000000; timeout 600 ... )`: `dart format --output=none --set-exit-if-changed packages test` (0 changed), `dart analyze --fatal-infos` (`No issues found!`), `dart test` (code rules). From `packages/typed_graphql`: `dart test -j 2` (everything passes).

```bash
git add .gitignore .github/workflows/ci.yml packages/typed_graphql/dartdoc_options.yaml packages/typed_graphql/lib packages/typed_graphql/test/doc
git commit -m "docs(typed_graphql): group the API reference in dartdoc categories

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Task 9: The example, the README, the root README, the CHANGELOG and CLAUDE.md

**Files:**
- Create: `packages/typed_graphql/example/example.dart`, `packages/typed_graphql/test/doc/example_test.dart`
- Modify (replace): `packages/typed_graphql/README.md`
- Modify: `README.md` (root), `packages/typed_graphql/CHANGELOG.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: the guides (the README table links to them by path; the link test of Task 2 resolves each).
- Produces: `example/example.dart` equal to the first program of the package README (a test keeps them equal), which pub.dev shows as the package example.

- [ ] **Step 1: Write the failing test**

Create `packages/typed_graphql/test/doc/example_test.dart`:

````dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'doc_snippet.dart';

/// The package README shows `example/example.dart` as its quick tour: the
/// two must not drift apart (R11.2).
void main() {
  test('the first program in the README is example/example.dart', () {
    final readme = File('README.md').readAsStringSync();
    final first = const DocSnippets().of('README.md', readme).first;
    final example = File('example/example.dart').readAsStringSync();
    expect(first.code.trimRight(), example.trimRight());
  });
}
````

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc/example_test.dart )`
Expected: FAIL, `Cannot open file, path = 'example/example.dart'`.

- [ ] **Step 2: Write the example**

Create `packages/typed_graphql/example/example.dart`:

````dart
import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  // Every syntax error in one pass, each with a stable code and a place.
  final broken = Source('query { a(x: ) }', name: 'bad.graphql');
  if (parser.parse(broken) case ParseFailure(:final diagnostics)) {
    diagnostics.forEach(stdout.writeln);
  }

  // A document prints back the way graphql-js prints it.
  final query = Source('query Hero{hero{name}}', name: 'hero.graphql');
  if (parser.parse(query) case ParseSuccess(:final document)) {
    stdout.writeln(const Printer().print(document));
  }

  // SDL builds a schema; a problem in it is a diagnostic, not an exception.
  final sdl = Source('type Query { hero: String }', name: 'schema.graphql');
  final result = const SchemaBuilder().fromSdl(
    parser.parse(sdl).requireDocument(),
    source: sdl,
  );
  switch (result) {
    case BuildSuccess(:final schema):
      stdout.writeln('query root: ${schema.queryTypeName}');
    case BuildFailure(:final diagnostics):
      diagnostics.forEach(stdout.writeln);
  }
}
````

Run it: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 120 dart run example/example.dart )`
Expected output:

```text
bad.graphql:1:14: error GQL008: Unexpected ")".
query Hero {
  hero {
    name
  }
}
query root: Query
```

- [ ] **Step 3: Replace the package README**

The old README repeats the guides (five long programs). The new one is the basalt shape: badges, status, contents, install, one tour (the example) and a table of guides. Replace the whole file `packages/typed_graphql/README.md` with:

````markdown
# typed_graphql

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-core-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**GraphQL for Dart, written from scratch and fully typed: the language, the
type system, validation and the wire protocol, with diagnostics instead of
exceptions.** Pure Dart, depends only on `meta`, runs on the VM, AOT and the
web (dart2js and dart2wasm). Part of
[typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** This release has the diagnostics model, the
> protocol data types, the language (syntax trees, lexer, parser, printer,
> visitors, schema coordinates) and the schema (its model, building and
> extending it from SDL, printing it, scalar codecs). Schema validation and
> introspection arrive in M3b, and document validation in M4 (see the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).

## Contents

- [Install](#install)
- [A quick tour](#a-quick-tour)
- [Guides](#guides)
- [License](#license)

## Install

Nothing is on pub.dev yet. To try it from the repository:

```yaml
dependencies:
  typed_graphql:
    git:
      url: https://github.com/4akloon/graphql_dart
      path: packages/typed_graphql
```

## A quick tour

Bad input never throws: a syntax error or a problem in the SDL is a value you
inspect. The same program is in [example/example.dart](example/example.dart).

```dart
import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  // Every syntax error in one pass, each with a stable code and a place.
  final broken = Source('query { a(x: ) }', name: 'bad.graphql');
  if (parser.parse(broken) case ParseFailure(:final diagnostics)) {
    diagnostics.forEach(stdout.writeln);
  }

  // A document prints back the way graphql-js prints it.
  final query = Source('query Hero{hero{name}}', name: 'hero.graphql');
  if (parser.parse(query) case ParseSuccess(:final document)) {
    stdout.writeln(const Printer().print(document));
  }

  // SDL builds a schema; a problem in it is a diagnostic, not an exception.
  final sdl = Source('type Query { hero: String }', name: 'schema.graphql');
  final result = const SchemaBuilder().fromSdl(
    parser.parse(sdl).requireDocument(),
    source: sdl,
  );
  switch (result) {
    case BuildSuccess(:final schema):
      stdout.writeln('query root: ${schema.queryTypeName}');
    case BuildFailure(:final diagnostics):
      diagnostics.forEach(stdout.writeln);
  }
}
```

It prints:

```text
bad.graphql:1:14: error GQL008: Unexpected ")".
query Hero {
  hero {
    name
  }
}
query root: Query
```

## Guides

Each guide is a short, runnable walk through one layer; every program in them
is run by the test suite, so what they print is what the package does.

| Guide | Covers |
|---|---|
| [Getting started](doc/getting_started.md) | The layers, the four rules, a first program |
| [Language](doc/language.md) | Parse, print, visit and rewrite documents; schema coordinates; tokens |
| [Diagnostics](doc/diagnostics.md) | Sources, spans, codes, the sink |
| [Wire protocol](doc/protocol.md) | `JsonValue`, requests, responses, errors |
| [Schema](doc/schema.md) | Build a schema from SDL, read it, extend it, print it |
| [Scalars and codecs](doc/scalars.md) | The built-in codecs and your own |

The API reference is generated by `dart doc` and groups every type under the
same topics. Run it in this directory and open `doc/api/index.html`.

## License

MIT — see [LICENSE](LICENSE).
````

Run: `cd packages/typed_graphql && ( ulimit -v 8000000; timeout 600 dart test test/doc )`
Expected: PASS: the README program runs and prints the text under `It prints:`, equals `example/example.dart`, and every README link resolves.

- [ ] **Step 4: Update the root README, the CHANGELOG and CLAUDE.md**

Root `README.md`: replace the `## Documentation` section's opening (the heading and the line `- [Roadmap](docs/roadmap.md) ...` starts the old list) so that it reads:

```markdown
## Documentation

Guides for the core package, `typed_graphql`. Every program in them is run by
the test suite, so what they print is what the package does:

- [Getting started](packages/typed_graphql/doc/getting_started.md) · [Language](packages/typed_graphql/doc/language.md) ·
  [Diagnostics](packages/typed_graphql/doc/diagnostics.md) · [Wire protocol](packages/typed_graphql/doc/protocol.md) ·
  [Schema](packages/typed_graphql/doc/schema.md) · [Scalars and codecs](packages/typed_graphql/doc/scalars.md)
- API reference: run `dart doc` in `packages/typed_graphql` and open
  `doc/api/index.html`; the types are grouped under the same topics.
- A runnable [example](packages/typed_graphql/example/example.dart)

For contributors and the design:

- [Roadmap](docs/roadmap.md) · [Requirements](docs/requirements.md) ·
  [Architecture](docs/superpowers/specs/2026-10-13-typed-graphql-design.md)
- [Research and decisions](docs/research/README.md)
- [CLAUDE.md](CLAUDE.md) — the repository guide for contributors and AI agents
```

(the last three bullets are the existing ones, unchanged).

`packages/typed_graphql/CHANGELOG.md`: append one bullet at the end of the `## 0.0.1 - Unreleased` list:

```markdown
- Documentation: six guides (getting started, language, diagnostics, wire
  protocol, schema, scalars and codecs), a runnable `example/example.dart`
  and `dart doc` categories for every exported type. The programs in the
  guides are run by the test suite.
```

`CLAUDE.md`: in the `## Where things are` list add

```markdown
- Guides: `packages/typed_graphql/doc/*.md`, tied to the dartdoc categories
  by `packages/typed_graphql/dartdoc_options.yaml`; the example is
  `packages/typed_graphql/example/example.dart`. The documentation suite is
  `packages/typed_graphql/test/doc/`.
```

and, in `## Code rules`, after the **Tests.** paragraph, add

```markdown
**Documentation.** A program in a guide is a fence tagged `dart`: complete
(imports and `main`), formatted by `dart format`, followed by a line ending
in `It prints:` and a `text` fence with its exact output; a fragment or a
signature is a `text` fence. A guide has no relative link (dartdoc breaks
it) and names another guide by its topic. Every exported public type has
`/// {@category <folder>}` in its doc comment (`schema/scalars/` is
`scalars`); a new exported folder needs its category in
`dartdoc_options.yaml` and its guide. `dart doc` reports 0 warnings. A stage
that adds API adds its section to the guide of its layer in the same commit.
```

Also change the `Status:` paragraph's last sentence to end "...and the SDL fuzzers. M3c (core documentation) delivers the guides, the example and the dartdoc categories."

- [ ] **Step 5: Format, analyze, test, commit**

From the root, each wrapped in `( ulimit -v 8000000; timeout 600 ... )`: `dart format --output=none --set-exit-if-changed packages test`, `dart analyze --fatal-infos` (this analyzes `example/` too: `avoid_print` is why the example writes with `stdout.writeln`), `dart test`. From `packages/typed_graphql`: `dart test -j 2`.
Expected: all clean.

```bash
git add README.md CLAUDE.md packages/typed_graphql/README.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/example packages/typed_graphql/test/doc/example_test.dart
git commit -m "docs(typed_graphql): add the example and trim the README to the guides

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Task 10: Whole-branch verification

**Files:** none (fixes, if any, go in a `docs(typed_graphql): ...` commit).

- [ ] **Step 1: The full matrix, one command at a time**

Each is wrapped as `( ulimit -v 8000000; timeout 600 <command> )`; run them one after another, never together.

| From | Command | Expected |
|---|---|---|
| root | `dart format --output=none --set-exit-if-changed packages test` | 0 changed |
| root | `dart analyze --fatal-infos` | `No issues found!` |
| root | `dart test` | all code rules pass |
| `packages/typed_graphql` | `dart test -j 2` | all pass, about 20 s; no program killed (`timed out`) |
| `packages/typed_graphql` | `dart test --compiler exe -j 1` | all pass; the program tests are skipped (`~`) |
| `packages/typed_graphql` | `dart doc` | `Found 0 warnings and 0 errors.`; then `rm -rf doc/api` |
| `packages/typed_graphql` | `dart pub publish --dry-run` | the file tree lists `doc/`, `example/` and `dartdoc_options.yaml`; the only warning allowed is about uncommitted files |

If Chrome is installed, also `dart test -p chrome --compiler dart2js` and `--compiler dart2wasm` from `packages/typed_graphql` (the `test/doc` files that use `dart:io` carry `@TestOn('vm')` and are skipped; the four pure helper tests should run on the web). Otherwise CI covers them.

- [ ] **Step 2: Size and rule check (CLAUDE.md self-review)**

Run: `wc -l packages/typed_graphql/test/doc/*.dart packages/typed_graphql/example/example.dart`
Expected: every file well under 500 lines (the longest is `snippet_runner.dart`, about 110). No method over 40 lines. Nothing unused: `DocFiles.all()` and `.guides()` both have callers.

- [ ] **Step 3: Read the guides once as a new reader**

Open `README.md`, then `doc/getting_started.md`, and follow "Where to go next" to each guide. Check that each guide names the other guides by topic only, that no sentence promises M3b or later work except the one closing sentence of `doc/schema.md` and the status paragraph of the README, and that a type used in a program is introduced in the text before it.

---

## Self-Review

**Spec coverage** (the M3c brief, R11):
- Six guides: Tasks 1 (getting started), 3 (diagnostics), 4 (protocol), 5 (language), 6 (schema), 7 (scalars); the merge of scalars into schema was weighed and rejected (Decisions).
- `dartdoc_options.yaml` with categories, tags and `dart doc` with 0 warnings: Task 8, enforced by `category_tags_test.dart` and the CI step.
- `example/example.dart`, trimmed README, root README Documentation section, CHANGELOG line: Task 9. Stub READMEs of the skeleton packages: deliberately not done (Decisions).
- Snippets cannot rot: Tasks 1, 2, 8, 9 (run, compare output, format, links, category, README = example).
- M3b not documented, with a named place: "How M3b extends these guides" and the last section of `doc/schema.md`.
- Every public member documented: unchanged, enforced by `public_member_api_docs`; Task 8 adds tags only.
- Green checks: Tasks 1, 2, 8, 9 and the matrix in Task 10.

**Placeholder scan:** the plan contains no "TBD" or "similar to Task N"; every file is given in full. The one forward-looking sentence in `doc/schema.md` and the README status paragraph state what is true (validation is not in this release) and say nothing about dates.

**Type consistency:** `MarkdownFences`, `DocSnippets`, `SnippetRunner` (`run`, `unformattedPlaces`, `isAvailable`, `timeLimit`), `DocFiles` (`guides`, `all`), `MarkdownLinks` (`relativeIn`, `anchorsIn`) and `PublicTypes` (`declaredIn`) keep their names and signatures in every task that uses them; the categories named in `dartdoc_options.yaml` are the folder names used by `categoryOf` in the test and by the tagging script.

**Review Focus:** each of the six lines maps to a test: 1 to the output assertions and the CI matrix, 2 to `doc_links_test.dart`, 3 to `snippet_runner_test.dart` ("kills a program that runs past the time limit"), 4 to `category_tags_test.dart`, 5 to the `--compiler exe` step of Tasks 1 and 10, 6 to `example_test.dart` and the format test.

**Verified before writing:** every program in the guides, the example and the README tour was run against the code of `main` (M1, M2 and M3a) in a scratch copy of the workspace: 211 documentation tests pass in about 20 s; `dart format`, `dart analyze --fatal-infos`, the root `dart test`, the package `dart test`, `dart test --compiler exe`, `dart doc` (0 warnings) and `dart pub publish --dry-run` were green there. Measured: no run used more than the 8 GB ulimit; a run that was killed once (exit 137, during the session's out-of-memory event) did not reproduce in several reruns under the limit, and the runner now bounds each program.

## Execution Handoff

Plan complete. Tasks are documentation tasks with real checks: recommended execution is **subagent-driven** with a fresh `implementer` (sonnet) per task and a `reviewer` (sonnet) after Tasks 1, 8 and 9; Tasks 3 to 7 are copy-and-verify and can be implemented back to back. Tasks 1 and 2 must go first (the guide tests), then 3 to 7 in any order, then 8, 9, 10. A final whole-branch review with `opus` reads the six guides as a new reader would.
