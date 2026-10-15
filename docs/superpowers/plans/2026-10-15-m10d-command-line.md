# M10d Command Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `generate` and `check` command line of `typed_graphql_codegen` (reading the configuration, the schema from a file or an introspection URL, the documents; writing only changed files; `GQL509`, `GQL510`), kept out of the engine's barrel; the guide's Command line section, the checked-in example project, the discovery query, `llms.txt`, `CLAUDE.md` and the handoff; then the fixes of the M10d review (I/O and HTTP failures as diagnostics, secrets never printed, `JsonMerger` and null).

**Architecture:** `bin/typed_graphql_codegen.dart` runs `CodegenCommand` (`lib/src/cli/`, the only `dart:io` user, not exported from the barrel). `CodegenCommandLine` parses the arguments (`args`; exit 64 on misuse). `ProjectReader` reads the configuration, the schema (a file, or `SchemaFetcher` posting `IntrospectionQuery.full` with the headers `HeaderExpander` fills from the environment) and the documents (`glob`, symbolic links not followed) into `ProjectFile`s; the engine generates; `OutputWriter` writes only the files that changed, through a temporary file and a rename, or reports them (`check`, `GQL509`); `DiagnosticPrinter` prints `path:line:col: severity code: message` with the excerpt, after `SecretRedactor` hides header values and URL credentials. Exit codes 0, 1, 64.

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, null-aware elements, patterns, sealed classes, records), `package:test`, `package:meta`; in the codegen package `yaml`, `crypto`, `path`, and in its command line `args`, `glob` and `dart:io`. No `analyzer`, no `dart_style`, no `package:gql`.

**Spec:** `docs/superpowers/specs/2026-10-15-m10-client-codegen-design.md` (sections 2, 3, 12-14, 16), `docs/requirements.md` R7.1, R7.10, R0.3, R11.1-R11.3.

**Base:** the M10a, M10b and M10c plans applied on `main` at `57f85e8`. The final whole-branch review may add fix commits; this plan is regenerated with one task per commit.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` or `bin/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, not even a private one, examples included.
- Layering (spec section 2): the core gains only `protocol/optional.dart` and the `GQL5xx` codes and still imports no platform library and no package but `meta` (R0.6); `typed_graphql_client` imports only the core; `typed_graphql_codegen` imports the core, `yaml`, `crypto`, `glob`, `path` and `args`.
- **The codegen engine has no `dart:io`.** Only `lib/src/cli/` and `bin/` import it; the engine takes `ProjectFile`s (path and text) and returns diagnostics and `GeneratedFile`s, so the CLI and M9's builder produce the same files. `test/quality/engine_imports_test.dart` checks it, and the barrel exports nothing that reaches `dart:io`.
- **No `analyzer`, no `dart_style`** (R6.5): the emitter lays the code out itself (`DartWriter`, 80 columns, `// dart format off` in the header).
- **Generated code passes strict analysis.** Every golden case compiles and passes `dart analyze --fatal-infos` with this repository's `analysis_options.yaml` plus `strict-casts` in a temporary package, and its decode / `toJson` round trip runs (`generated_code_test.dart`, tag `analysis`). Generated code silences no lint.
- Bad input never throws (R0.3): configuration, schema, documents, HTTP responses and files become diagnostics with a stable code and a place, or a `DecodeFailure` with a path. Only programmer errors throw (`ArgumentError`, `RangeError`, `StateError`).
- **No recursion over a document, a type or a plan.** Every walk uses an explicit stack (deep input overflows the stack on the web long before the VM); generated decoders nest one call per selection level, bounded by the parser's depth limit.
- **Deterministic output** (R7.10): inputs sorted by path, declarations in document order, schema types, imports and manifest entries sorted; no hash-ordered collection is iterated for output.
- New codes go into `DiagnosticCode` in id order, with a doc comment, in their own `feat(typed_graphql)` commit before the commit that first reports them. The final numbering is `GQL500`-`GQL511` (spec section 9).
- Public API goes through each package's barrel, each exported type tagged with its dartdoc category (`codegen`, `operations` for the client, `protocol` for `Optional`); internal collaborators stay out of it.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- **Memory and time limits when running the suites.** Run every `dart test`, `dart analyze`, `dart format`, `dart doc` and `dart pub` command under `ulimit -v 8000000` and `timeout`, one Dart process at a time; the M10 suites are the core's, `typed_graphql_client`'s and `typed_graphql_codegen`'s, and the codegen analysis test starts `dart pub get`, `dart analyze` and `dart run` in a temporary package. Chrome cannot start under `ulimit -v`; bound the browser runs (core and client only) by resident memory: `systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome …`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action.
- Commits use Conventional Commits, one per task, with the message and the trailer given in the task.
- Run every command from the repository root unless a step says otherwise; use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are unified diffs against the tree the earlier tasks leave; each is the content of a commit on the branch `m10-final` that passed the green check. A CHANGELOG change is "Append to". If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- Golden files (`test/goldens/<case>/`: `*.dart.golden`, `*.txt`, inputs and support files) are test files; `UPDATE_GOLDENS=1 dart test test/golden_test.dart` rewrites the outputs, but the plan gives them as committed.

## Review Focus

1. Secrets never reach the output: a header value (Task 4, `schema_fetcher_test.dart` "a header value never appears in the output"); a body that echoes the header, with control characters escaped, and a token in the URL's query or user information (Task 8, "a body that echoes the header hides it and escapes controls", "a token in the URL is never printed").
2. A hostile or broken server is a `GQL510` within bounds: a body past the 64 MiB cap, counted while reading (Task 8, "a body past the cap is GQL510"); a redirect, not followed (Task 8, "a redirect is GQL510 with the target and no query"); a slow server and a closed port (Task 4, "a slow server past the timeout is GQL510", "a closed port is GQL510").
3. The file system: a symbolic link to a document is not followed, an invalid glob is `GQL501`, a directory at an output path is `GQL510` and the rest is written (Task 8, `project_reading_test.dart` "a symbolic link to a document is not followed", "an invalid documents pattern is GQL501"; `output_writer_test.dart` "a directory at an output path is GQL510 and the rest is written"); `generate` never deletes (Task 2, `codegen_command_test.dart` "generate never deletes a stale generated file").
4. The engine barrel reaches no `dart:io` (Task 3, `engine_imports_test.dart` "no library the barrel reaches imports dart:io").
5. The checked-in example is what the generator writes, byte for byte (Task 5, `example_test.dart` "${file.path} equals the checked-in file").

## File map

| File | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart` | Test support | 2 |
| `packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart` | Runs the code generator's command line, with injected streams and working directory so tests run it in process | 2 |
| `packages/typed_graphql_codegen/lib/src/cli/codegen_command_line.dart` | The command line of the code generator | 2 |
| `packages/typed_graphql_codegen/lib/src/cli/command_line_result.dart` | What [CodegenCommandLine.parse] found | 2 |
| `packages/typed_graphql_codegen/lib/src/cli/diagnostic_printer.dart` | Prints diagnostics for a terminal | 2 |
| `packages/typed_graphql_codegen/lib/src/cli/output_writer.dart` | Writes generated files under the project directory, or reports which of them are out of date | 2 |
| `packages/typed_graphql_codegen/lib/src/cli/project_read_result.dart` | What [ProjectReader] found on disk | 2 |
| `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart` | Reads the configuration, the schema file and the documents of a project from disk | 2 |
| `packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart` | Tests | 2 |
| `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart` | Tests | 2 |
| `packages/typed_graphql_codegen/test/support/cli_project.dart` | A temporary project copied from the `operations` golden input, and the way to run the command line in it | 2 |
| `packages/typed_graphql_codegen/lib/src/cli/header_expander.dart` | Replaces `${NAME}` in header values by environment variables | 4 |
| `packages/typed_graphql_codegen/lib/src/cli/schema_fetch_result.dart` | What [SchemaFetcher] got from a schema URL | 4 |
| `packages/typed_graphql_codegen/lib/src/cli/schema_fetcher.dart` | Fetches a schema by posting the full introspection query to a URL | 4 |
| `packages/typed_graphql_codegen/test/cli/header_expander_test.dart` | Tests | 4 |
| `packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart` | Tests | 4 |
| `packages/typed_graphql_codegen/example/README.md` | Document | 5 |
| `packages/typed_graphql_codegen/example/lib/schema.graphql.dart` | The enum `Role` | 5 |
| `packages/typed_graphql_codegen/example/lib/user.graphql` | Document | 5 |
| `packages/typed_graphql_codegen/example/lib/user.graphql.dart` | The query `GetUser` | 5 |
| `packages/typed_graphql_codegen/example/pubspec.yaml` | Document | 5 |
| `packages/typed_graphql_codegen/example/schema.graphql` | Document | 5 |
| `packages/typed_graphql_codegen/example/typed_graphql.yaml` | Document | 5 |
| `packages/typed_graphql_codegen/test/example_test.dart` | Tests | 5 |
| `packages/typed_graphql_codegen/lib/src/cli/secret_redactor.dart` | Keeps secrets and terminal control characters out of what the command line prints | 8 |
| `packages/typed_graphql_codegen/test/cli/output_writer_test.dart` | Tests | 8 |
| `packages/typed_graphql_codegen/test/cli/project_reading_test.dart` | Tests | 8 |
| `packages/typed_graphql_codegen/test/goldens/operations/` | Golden case (2 new files) | 10 |
| `packages/typed_graphql_codegen/lib/src/emit/doc_comment_escaper.dart` | Makes schema text safe inside a `///` comment | 11 |
| `packages/typed_graphql_codegen/test/emit/doc_comment_escaper_test.dart` | Tests | 11 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modified | 1, 6, 12 |
| `packages/typed_graphql_codegen/CHANGELOG.md` | Modified | 2, 4, 5, 9 |
| `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart` | Modified | 2, 3, 15 |
| `packages/typed_graphql_codegen/pubspec.yaml` | Modified | 2 |
| `packages/typed_graphql_codegen/test/quality/engine_imports_test.dart` | Modified | 3 |
| `packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart` | Modified | 4 |
| `CLAUDE.md` | Modified | 5, 15 |
| `docs/discovery.md` | Modified | 5 |
| `docs/superpowers/HANDOFF.md` | Modified | 5, 16 |
| `llms.txt` | Modified | 5 |
| `packages/typed_graphql_codegen/README.md` | Modified | 5, 9 |
| `packages/typed_graphql_codegen/doc/client_codegen.md` | Modified | 5, 9, 12, 13 |
| `pubspec.yaml` | Modified | 5 |
| `packages/typed_graphql_client/CHANGELOG.md` | Modified | 7 |
| `packages/typed_graphql_client/lib/src/operation/json_merger.dart` | Modified | 7 |
| `packages/typed_graphql_client/test/operation/json_merger_test.dart` | Modified | 7 |
| `packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt` | Modified | 8 |
| `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart` | Modified | 10 |
| `packages/typed_graphql_codegen/test/emit/dart_names_test.dart` | Modified | 10 |
| `packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql` | Modified | 10, 11 |
| `packages/typed_graphql_codegen/test/goldens/operations/output/build/persisted_operations.json.golden` | Modified | 10 |
| `packages/typed_graphql_codegen/test/goldens/operations/output/lib/schema.graphql.dart.golden` | Modified | 10 |
| `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart` | Modified | 11 |
| `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart` | Modified | 11 |
| `README.md` | Modified | 15 |

## The green check

Every task ends with this check. "Green" means each command exits 0:

```sh
ulimit -v 8000000
timeout 300 dart pub get
timeout 300 dart format --output=none --set-exit-if-changed packages test
timeout 600 dart analyze --fatal-infos
timeout 600 dart test
for p in packages/*/; do (cd "$p" && timeout 900 dart test) || exit 1; done
```

Run a new test file alone first under the same limits. The core, client and codegen suites include the documentation tests, which run each guide program as a `dart` process; the codegen suite also runs the analysis test (tag `analysis`), which creates a temporary package per golden case. If a run is killed (exit 137) or times out (exit 124), find the cause before going on.

After the last task, also run the M10 packages on every compiler (Chrome only for the core; the client's Chrome runs are deferred to M11 and the codegen package is VM-only):

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 900 dart test --compiler exe test/protocol test/diagnostics)
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 900 dart test --compiler exe)
(cd packages/typed_graphql && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2js test/protocol)
(cd packages/typed_graphql && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2wasm test/protocol)
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 900 dart test --compiler exe)
```

Under `--compiler exe` the codegen tests that start the `dart` tool (the analysis test, the CLI exit-code test) skip themselves with a reason: `Platform.resolvedExecutable` is the compiled test, not `dart`.

---

### Task 1: Add the CLI codes GQL509 and GQL510

The core catalog gains `GQL509` outputOutdated (a generated file that differs from what the generator would write, reported by `check`) and `GQL510` inputUnreadable (a configuration, schema or document file the command line cannot read), in their own commit before Task 2 reports them.

Commit on the branch: `0361110`.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: The core `DiagnosticCode`.
- Produces:
- Diagnostic codes: `GQL509`, `GQL510`.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -551,6 +551,15 @@ enum DiagnosticCode(
   /// mapped to.
   reservedTypeName('GQL508'),
 
+  /// `GQL509`: `check` found a generated file that is missing or differs from
+  /// what `generate` would write; reported without a span.
+  outputOutdated('GQL509'),
+
+  /// `GQL510`: a file the command line must read, such as the configuration,
+  /// the schema or a document, or the schema URL, cannot be read; reported
+  /// without a span.
+  inputUnreadable('GQL510'),
+
   /// `GQL511`: an operation or fragment whose selections would make the code
   /// generator declare more classes than its fixed limit (10000); reported at
   /// the operation or fragment name.
```

- [ ] **Step 2: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
git commit -q -m "feat(typed_graphql): add the CLI codes GQL509 and GQL510" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Add the generate and check commands

The command line (spec section 12): `CodegenCommandLine` parses the arguments, `ProjectReader` reads the configuration, the schema file and the documents into a `ProjectReadResult`, the engine generates, and `OutputWriter` writes the changed files (`generate`) or reports the outdated ones (`check`, `GQL509`); `DiagnosticPrinter` prints each diagnostic with its excerpt. A file that cannot be read is `GQL510`. Adds `args`, `glob` and `bin/typed_graphql_codegen.dart`.

Commit on the branch: `e004971`.

**Files:**
- Create: `packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart`, `packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart`, `packages/typed_graphql_codegen/lib/src/cli/codegen_command_line.dart`, `packages/typed_graphql_codegen/lib/src/cli/command_line_result.dart`, `packages/typed_graphql_codegen/lib/src/cli/diagnostic_printer.dart`, `packages/typed_graphql_codegen/lib/src/cli/output_writer.dart`, `packages/typed_graphql_codegen/lib/src/cli/project_read_result.dart`, `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, `packages/typed_graphql_codegen/pubspec.yaml`
- Test: `packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart`, `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`, `packages/typed_graphql_codegen/test/support/cli_project.dart`

**Interfaces:**
- Consumes: M10a-M10c `CodegenConfig`, `ClientGenerator.generate`, `GenerationResult`, `ProjectFile`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// cli/codegen_command.dart
final class const CodegenCommand(…)
  int run(List<String> arguments)

// cli/codegen_command_line.dart
final class const CodegenCommandLine()
  String get usage
  CommandLineResult parse(List<String> arguments)

// cli/command_line_result.dart
sealed class CommandLineResult
  const CommandLineResult()
final class const CommandLineRun(…)
final class const CommandLineHelp() extends CommandLineResult
final class const CommandLineUsageError(…)

// cli/diagnostic_printer.dart
final class const DiagnosticPrinter()
  String print(Diagnostic diagnostic)

// cli/output_writer.dart
final class const OutputWriter(…)
  List<String> write(List<GeneratedFile> files)
  List<Diagnostic> outdated(List<GeneratedFile> files)

// cli/project_read_result.dart
sealed class ProjectReadResult
  const ProjectReadResult()
final class ProjectRead(…)
final class ProjectReadFailed(…)

// cli/project_reader.dart
final class const ProjectReader(…)
  ProjectReadResult read(String configName)
sealed class _ReadOutcome
final class _Text extends _ReadOutcome
  final String text
final class _Failed extends _ReadOutcome
  final Diagnostic problem
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

import '../support/cli_project.dart';

void main() {
  late CliProject project;
  setUp(() => project = CliProject());
  tearDown(() => project.delete());

  test('no command is a usage error', () {
    expect(project.run([]), 64);
    expect(project.err.toString(), startsWith('Missing command.\nUsage:'));
  });

  test('an unknown command is a usage error', () {
    expect(project.run(['build']), 64);
    expect(project.err.toString(), contains('Unknown command "build".'));
  });

  test('an unknown option is a usage error', () {
    expect(project.run(['generate', '--nope']), 64);
    expect(project.err.toString(), contains('Could not find an option'));
  });

  test('--help prints the usage and succeeds', () {
    expect(project.run(['--help']), 0);
    expect(project.out.toString(), '${const CodegenCommandLine().usage}\n');
    expect(project.err.toString(), isEmpty);
  });
}
```

Create `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_project.dart';

void main() {
  late CliProject project;
  setUp(() => project = CliProject());
  tearDown(() => project.delete());

  const generated = 'lib/user.graphql.dart';

  test('generate writes the files of the goldens', () {
    expect(project.run(['generate']), 0);
    expect(project.out.toString(), 'Wrote 5 files.\n');
    for (final golden in Directory(
      'test/goldens/operations/output',
    ).listSync(recursive: true).whereType<File>()) {
      final path = golden.path.substring(
        'test/goldens/operations/output/'.length,
        golden.path.length - '.golden'.length,
      );
      expect(project.file(path).readAsStringSync(), golden.readAsStringSync());
    }
  });

  test('a second generate writes nothing', () {
    project.run(['generate']);
    expect(project.run(['generate']), 0);
    expect(project.out.toString(), 'Nothing to write.\n');
  });

  test('check after generate is clean', () {
    project.run(['generate']);
    expect(project.run(['check']), 0);
    expect(project.out.toString(), 'Up to date.\n');
  });

  test('check reports a missing file and writes nothing', () {
    expect(project.run(['check']), 1);
    expect(
      project.err.toString(),
      contains(
        "error GQL509: The generated file 'build/persisted_operations.json' "
        'is out of date; run `dart run typed_graphql_codegen generate`.',
      ),
    );
    expect(project.file(generated).existsSync(), isFalse);
  });

  test('check reports an edited file and does not rewrite it', () {
    project.run(['generate']);
    project.file(generated).writeAsStringSync('// edited\n');
    expect(project.run(['check']), 1);
    expect(
      project.err.toString(),
      "error GQL509: The generated file '$generated' is out of date; run "
      '`dart run typed_graphql_codegen generate`.\n',
    );
    expect(project.file(generated).readAsStringSync(), '// edited\n');
  });

  test('a missing schema file is GQL510', () {
    project.file('schema.graphql').deleteSync();
    expect(project.run(['generate']), 1);
    expect(
      project.err.toString(),
      startsWith("error GQL510: Cannot read 'schema.graphql': "),
    );
  });

  test('a missing configuration is GQL510', () {
    expect(project.run(['generate', '--config', 'other.yaml']), 1);
    expect(
      project.err.toString(),
      startsWith("error GQL510: Cannot read 'other.yaml': "),
    );
  });

  test('a syntax error prints its place and excerpt', () {
    project.file('lib/x.graphql').writeAsStringSync('query Q {\n');
    expect(project.run(['generate']), 1);
    expect(project.err.toString(), startsWith('lib/x.graphql:2:1: error GQL'));
    expect(project.err.toString(), contains('1 | query Q {'));
  });

  test('a warning alone exits 0', () {
    for (final path in ['user', 'user_mutations', 'user_subscriptions']) {
      project.file('lib/$path.graphql').deleteSync();
    }
    expect(project.run(['generate']), 0);
    expect(project.err.toString(), contains('warning GQL506'));
  });

  test('a document outside the glob is ignored', () {
    project.file('other/z.graphql').createSync(recursive: true);
    project.file('other/z.graphql').writeAsStringSync('query {');
    expect(project.run(['generate']), 0);
    expect(project.file('other/z.graphql.dart').existsSync(), isFalse);
  });

  test('generate never deletes a stale generated file', () {
    project.run(['generate']);
    project.file('lib/user_mutations.graphql').deleteSync();
    expect(project.run(['generate']), 0);
    expect(
      project.file('lib/user_mutations.graphql.dart').existsSync(),
      isTrue,
    );
  });

  test('the executable passes the exit code to the process', () {
    final result = Process.runSync(Platform.resolvedExecutable, [
      'run',
      '${Directory.current.path}/bin/typed_graphql_codegen.dart',
      'check',
      '--config',
      '${project.directory.path}/typed_graphql.yaml',
    ]);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('GQL509'));
  });
}
```

Create `packages/typed_graphql_codegen/test/support/cli_project.dart`:

```dart
import 'dart:io';

import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

/// A temporary project copied from the `operations` golden input, and the
/// way to run the command line in it.
final class CliProject {
  /// Copies the input into a new temporary directory.
  CliProject()
    : directory = Directory.systemTemp.createTempSync('codegen_cli') {
    final input = Directory('test/goldens/operations/input');
    for (final entity in input.listSync(recursive: true)) {
      if (entity is! File) continue;
      final target = File(
        '${directory.path}/${entity.path.substring(input.path.length + 1)}',
      );
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(entity.readAsStringSync());
    }
  }

  /// The project directory.
  final Directory directory;

  /// Everything written to the output stream by the last [run].
  final StringBuffer out = StringBuffer();

  /// Everything written to the error stream by the last [run].
  final StringBuffer err = StringBuffer();

  /// Runs [arguments] in the project; returns the exit code.
  int run(List<String> arguments) {
    out.clear();
    err.clear();
    return CodegenCommand(out, err, directory.path).run(arguments);
  }

  /// The file at [path], relative to the project.
  File file(String path) => File('${directory.path}/$path');

  /// Deletes the project.
  void delete() => directory.deleteSync(recursive: true);
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_line_test.dart test/cli/codegen_command_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Update the package files**

In `packages/typed_graphql_codegen/pubspec.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,11 +6,16 @@ repository: https://github.com/4akloon/graphql_dart/tree/main/packages/typed_gra
 issue_tracker: https://github.com/4akloon/graphql_dart/issues
 topics: [graphql]
 
+executables:
+  typed_graphql_codegen:
+
 environment:
   sdk: ^3.13.0
 
 dependencies:
+  args: ^2.7.0
   crypto: ^3.0.6
+  glob: ^2.1.3
   path: ^1.9.0
   typed_graphql: ^0.0.1
   yaml: ^3.1.3
```

- [ ] **Step 4: Write the implementation**

Create `packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart`:

```dart
import 'dart:io';

import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main(List<String> arguments) {
  exitCode = CodegenCommand(
    stdout,
    stderr,
    Directory.current.path,
  ).run(arguments);
}
```

Create `packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../generator/client_generator.dart';
import 'codegen_command_line.dart';
import 'command_line_result.dart';
import 'diagnostic_printer.dart';
import 'output_writer.dart';
import 'project_read_result.dart';
import 'project_reader.dart';

/// Runs the code generator's command line, with injected streams and working
/// directory so tests run it in process.
///
/// {@category codegen}
final class const CodegenCommand(
  /// Where normal output goes.
  final StringSink out,

  /// Where diagnostics and usage errors go.
  final StringSink err,

  /// The directory relative `--config` paths are resolved against.
  final String workingDirectory,
) {
  /// Creates a command that writes to [out] and [err].
  this;

  /// The exit code of a usage error.
  static const int usageExitCode = 64;

  /// Runs [arguments]; returns the process exit code.
  int run(List<String> arguments) {
    const commandLine = CodegenCommandLine();
    switch (commandLine.parse(arguments)) {
      case CommandLineHelp():
        out.writeln(commandLine.usage);
        return 0;
      case CommandLineUsageError(:final message):
        err.writeln(message);
        err.writeln(commandLine.usage);
        return usageExitCode;
      case CommandLineRun(:final isCheck, :final configPath):
        return _run(isCheck: isCheck, configPath: configPath);
    }
  }

  int _run({required bool isCheck, required String configPath}) {
    final absolute = p.normalize(p.absolute(workingDirectory, configPath));
    final directory = p.dirname(absolute);
    final project = ProjectReader(directory).read(p.basename(absolute));
    if (project is! ProjectRead) {
      return _report((project as ProjectReadFailed).diagnostics);
    }
    final result = ClientGenerator(
      project.config,
    ).generate(schema: project.schema, documents: project.documents);
    if (result.hasErrors) return _report(result.diagnostics);
    final writer = OutputWriter(directory);
    if (isCheck) {
      final outdated = writer.outdated(result.files);
      final code = _report([...result.diagnostics, ...outdated]);
      if (outdated.isEmpty) out.writeln('Up to date.');
      return code;
    }
    final written = writer.write(result.files);
    final code = _report(result.diagnostics);
    out.writeln(
      written.isEmpty ? 'Nothing to write.' : 'Wrote ${written.length} files.',
    );
    return code;
  }

  int _report(List<Diagnostic> diagnostics) {
    const printer = DiagnosticPrinter();
    for (final diagnostic in diagnostics) {
      err.writeln(printer.print(diagnostic));
    }
    return diagnostics.any((diagnostic) => diagnostic.isError) ? 1 : 0;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/cli/codegen_command_line.dart`:

```dart
import 'package:args/args.dart';

import 'command_line_result.dart';

/// The command line of the code generator: `generate` or `check`, and
/// `--config`.
///
/// {@category codegen}
final class const CodegenCommandLine() {
  /// Creates the parser.
  this;

  /// The configuration file name when `--config` is not given.
  static const String defaultConfigPath = 'typed_graphql.yaml';

  /// The usage text shown for `--help` and after a usage error.
  String get usage =>
      'Usage: typed_graphql_codegen <generate|check> [--config <file>]\n\n'
      'Commands:\n'
      '  generate  Write the generated files.\n'
      '  check     Fail when a generated file is missing or out of date.\n\n'
      '${_parser.usage}';

  ArgParser get _parser => ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      defaultsTo: defaultConfigPath,
      help: 'The configuration file.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  /// Reads [arguments]; a mistake is a [CommandLineUsageError], never a throw.
  CommandLineResult parse(List<String> arguments) {
    final ArgResults results;
    try {
      results = _parser.parse(arguments);
    } on FormatException catch (error) {
      return CommandLineUsageError(error.message);
    }
    if (results.flag('help')) return const CommandLineHelp();
    final rest = results.rest;
    if (rest.isEmpty) return const CommandLineUsageError('Missing command.');
    if (rest.length > 1 ||
        (rest.single != 'generate' && rest.single != 'check')) {
      return CommandLineUsageError('Unknown command "${rest.join(' ')}".');
    }
    return CommandLineRun(rest.single == 'check', results.option('config')!);
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/cli/command_line_result.dart`:

```dart
/// What [CodegenCommandLine.parse] found.
///
/// {@category codegen}
sealed class CommandLineResult {
  const CommandLineResult();
}

/// Run `generate`, or `check` when [isCheck].
///
/// {@category codegen}
final class const CommandLineRun(
  /// Whether the command is `check`.
  final bool isCheck,

  /// The configuration file path as given.
  final String configPath,
) extends CommandLineResult {
  /// Creates a run request.
  this;
}

/// `--help` was given.
///
/// {@category codegen}
final class const CommandLineHelp() extends CommandLineResult {
  /// Creates the request.
  this;
}

/// The arguments are wrong; [message] says how.
///
/// {@category codegen}
final class const CommandLineUsageError(
  /// What is wrong.
  final String message,
) extends CommandLineResult {
  /// Creates the error.
  this;
}
```

Create `packages/typed_graphql_codegen/lib/src/cli/diagnostic_printer.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Prints diagnostics for a terminal.
///
/// {@category codegen}
final class const DiagnosticPrinter() {
  /// Creates the printer.
  this;

  /// [diagnostic] as `path:line:col: severity GQLnnn: message`, then the
  /// excerpt of its span and a note per related span; without a span,
  /// `severity GQLnnn: message`.
  String print(Diagnostic diagnostic) {
    final lines = <String>[diagnostic.toString()];
    final span = diagnostic.span;
    if (span != null) lines.add(span.excerpt);
    for (final place in diagnostic.related) {
      lines.add('$place: note: related');
    }
    return lines.join('\n');
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/cli/output_writer.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../generator/generated_file.dart';

/// Writes generated files under the project directory, or reports which of
/// them are out of date.
///
/// {@category codegen}
final class const OutputWriter(
  /// The directory of the configuration file; generated paths are relative
  /// to it.
  final String directory,
) {
  /// Creates a writer for the project in [directory].
  this;

  /// Writes every file of [files] whose content differs; never deletes.
  /// Returns the paths written.
  List<String> write(List<GeneratedFile> files) {
    final written = <String>[];
    for (final generated in files) {
      if (_isCurrent(generated)) continue;
      final file = File(p.join(directory, generated.path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(generated.text);
      written.add(generated.path);
    }
    return written;
  }

  /// A `GQL509` per file of [files] that is missing or differs; writes
  /// nothing.
  List<Diagnostic> outdated(List<GeneratedFile> files) => [
    for (final generated in files)
      if (!_isCurrent(generated))
        Diagnostic(
          .outputOutdated,
          .error,
          "The generated file '${generated.path}' is out of date; run "
          '`dart run typed_graphql_codegen generate`.',
        ),
  ];

  bool _isCurrent(GeneratedFile generated) {
    final file = File(p.join(directory, generated.path));
    return file.existsSync() && file.readAsStringSync() == generated.text;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/cli/project_read_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../project/project_file.dart';

/// What [ProjectReader] found on disk.
///
/// {@category codegen}
sealed class ProjectReadResult {
  const ProjectReadResult();
}

/// Everything the generator reads.
///
/// {@category codegen}
final class ProjectRead(
  /// The parsed configuration.
  final CodegenConfig config,

  /// The schema file.
  final ProjectFile schema,
  List<ProjectFile> documents,
) extends ProjectReadResult {
  /// Creates the result.
  this;

  /// The matched documents, sorted by path.
  final List<ProjectFile> documents = List.unmodifiable(documents);
}

/// The project could not be read; [diagnostics] say why.
///
/// {@category codegen}
final class ProjectReadFailed(
  List<Diagnostic> diagnostics,
) extends ProjectReadResult {
  /// Creates the result.
  this;

  /// The problems, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
```

Create `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`:

```dart
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../config/config_result.dart';
import '../config/schema_location.dart';
import '../project/project_file.dart';
import 'project_read_result.dart';

/// Reads the configuration, the schema file and the documents of a project
/// from disk.
///
/// {@category codegen}
final class const ProjectReader(
  /// The directory of the configuration file; every path is relative to it.
  final String directory,
) {
  /// Creates a reader for the project in [directory].
  this;

  /// Reads the project whose configuration is the file [configName].
  ProjectReadResult read(String configName) {
    final configText = _readText(configName);
    if (configText is _Failed) return ProjectReadFailed([configText.problem]);
    final parsed = CodegenConfig.parse(
      (configText as _Text).text,
      path: configName,
    );
    if (parsed is ConfigFailure) return ProjectReadFailed(parsed.diagnostics);
    final config = (parsed as ConfigSuccess).config;
    final location = config.schema;
    if (location is! SchemaFile) {
      return ProjectReadFailed([
        _unreadable(
          '${location is SchemaUrl ? location.url : location}',
          'Fetching a schema URL is not supported here.',
        ),
      ]);
    }
    return _readSources(config, location.path);
  }

  ProjectReadResult _readSources(CodegenConfig config, String schemaPath) {
    final schema = _readText(schemaPath);
    if (schema is _Failed) return ProjectReadFailed([schema.problem]);
    final problems = <Diagnostic>[];
    final documents = <ProjectFile>[];
    for (final path in _documentPaths(config, schemaPath)) {
      final text = _readText(path);
      switch (text) {
        case _Text():
          documents.add(ProjectFile(path, text.text));
        case _Failed():
          problems.add(text.problem);
      }
    }
    if (problems.isNotEmpty) return ProjectReadFailed(problems);
    return ProjectRead(
      config,
      ProjectFile(schemaPath, (schema as _Text).text),
      documents,
    );
  }

  List<String> _documentPaths(CodegenConfig config, String schemaPath) {
    final paths = <String>{};
    for (final pattern in config.documents) {
      for (final entity in Glob(pattern).listSync(root: directory)) {
        if (entity is! File || !entity.path.endsWith('.graphql')) continue;
        final relative = p.posix.joinAll(
          p.split(p.relative(entity.path, from: directory)),
        );
        if (relative != schemaPath) paths.add(relative);
      }
    }
    return paths.toList()..sort();
  }

  _ReadOutcome _readText(String path) {
    try {
      return _Text(File(p.join(directory, path)).readAsStringSync());
    } on FileSystemException catch (error) {
      return _Failed(
        _unreadable(path, error.osError?.message ?? error.message),
      );
    } on FormatException catch (error) {
      return _Failed(_unreadable(path, error.message));
    }
  }

  Diagnostic _unreadable(String path, String reason) => Diagnostic(
    .inputUnreadable,
    .error,
    "Cannot read '$path': $reason.",
  );
}

sealed class _ReadOutcome {
  const _ReadOutcome();
}

final class _Text extends _ReadOutcome {
  const _Text(this.text);
  final String text;
}

final class _Failed extends _ReadOutcome {
  const _Failed(this.problem);
  final Diagnostic problem;
}
```

In `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,6 +6,13 @@
 /// objects of the schema; see the package README.
 library;
 
+export 'src/cli/codegen_command.dart';
+export 'src/cli/codegen_command_line.dart';
+export 'src/cli/command_line_result.dart';
+export 'src/cli/diagnostic_printer.dart';
+export 'src/cli/output_writer.dart';
+export 'src/cli/project_read_result.dart';
+export 'src/cli/project_reader.dart';
 export 'src/config/codegen_config.dart';
 export 'src/config/config_result.dart';
 export 'src/config/dart_reference.dart';
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_line_test.dart test/cli/codegen_command_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- `dart run typed_graphql_codegen generate` writes the generated files and
  `check` fails when one is missing or out of date (`GQL509`); a file the
  command cannot read is `GQL510`. `--config` names the configuration file.
  `generate` never deletes a file. `CodegenCommand` runs both in process.
```

- [ ] **Step 7: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart packages/typed_graphql_codegen/lib/src/cli/codegen_command_line.dart packages/typed_graphql_codegen/lib/src/cli/command_line_result.dart packages/typed_graphql_codegen/lib/src/cli/diagnostic_printer.dart packages/typed_graphql_codegen/lib/src/cli/output_writer.dart packages/typed_graphql_codegen/lib/src/cli/project_read_result.dart packages/typed_graphql_codegen/lib/src/cli/project_reader.dart packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart packages/typed_graphql_codegen/pubspec.yaml packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart packages/typed_graphql_codegen/test/cli/codegen_command_test.dart packages/typed_graphql_codegen/test/support/cli_project.dart
git commit -q -m "feat(typed_graphql_codegen): add the generate and check commands" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Keep the command line out of the library

Ruling on M10d Task 1: the CLI classes import `dart:io`, so the engine barrel no longer exports them (spec section 2; M9's builder and any non-VM user import the barrel). `bin/` and the tests import them from `src/cli/`, and a test walks the barrel's imports and exports and fails if any reaches `dart:io`.

Commit on the branch: `5a8fa6c`.

**Files:**
- Modify: `packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart`, `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`
- Test: `packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart`, `packages/typed_graphql_codegen/test/quality/engine_imports_test.dart`, `packages/typed_graphql_codegen/test/support/cli_project.dart`

**Interfaces:**
- Consumes: Task 2.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,7 +2,7 @@
 library;
 
 import 'package:test/test.dart';
-import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';
+import 'package:typed_graphql_codegen/src/cli/codegen_command_line.dart';
 
 import '../support/cli_project.dart';
 
```

In `packages/typed_graphql_codegen/test/quality/engine_imports_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,4 +20,31 @@ void main() {
     ];
     expect(offenders, isEmpty);
   });
+
+  test('no library the barrel reaches imports dart:io', () {
+    final pending = ['lib/typed_graphql_codegen.dart'];
+    final seen = <String>{};
+    final offenders = <String>[];
+    final directive = RegExp(
+      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
+      multiLine: true,
+    );
+    while (pending.isNotEmpty) {
+      final path = pending.removeLast();
+      if (!seen.add(path)) continue;
+      for (final match in directive.allMatches(
+        File(path).readAsStringSync(),
+      )) {
+        final target = match.group(1)!;
+        if (target == 'dart:io') offenders.add(path);
+        if (target.startsWith('package:') || target.startsWith('dart:')) {
+          continue;
+        }
+        pending.add(
+          Uri.file(path).resolve(target).toFilePath(),
+        );
+      }
+    }
+    expect(offenders, isEmpty);
+  });
 }
```

In `packages/typed_graphql_codegen/test/support/cli_project.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 import 'dart:io';
 
-import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';
+import 'package:typed_graphql_codegen/src/cli/codegen_command.dart';
 
 /// A temporary project copied from the `operations` golden input, and the
 /// way to run the command line in it.
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_line_test.dart test/quality/engine_imports_test.dart)
```

Expected: FAIL. The new and changed tests fail on the behaviour this task fixes (assertion failures; a test that uses a name the next step adds does not compile).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 import 'dart:io';
 
-import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';
+import 'package:typed_graphql_codegen/src/cli/codegen_command.dart';
 
 void main(List<String> arguments) {
   exitCode = CodegenCommand(
```

In `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,13 +6,6 @@
 /// objects of the schema; see the package README.
 library;
 
-export 'src/cli/codegen_command.dart';
-export 'src/cli/codegen_command_line.dart';
-export 'src/cli/command_line_result.dart';
-export 'src/cli/diagnostic_printer.dart';
-export 'src/cli/output_writer.dart';
-export 'src/cli/project_read_result.dart';
-export 'src/cli/project_reader.dart';
 export 'src/config/codegen_config.dart';
 export 'src/config/config_result.dart';
 export 'src/config/dart_reference.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_line_test.dart test/quality/engine_imports_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart packages/typed_graphql_codegen/test/quality/engine_imports_test.dart packages/typed_graphql_codegen/test/support/cli_project.dart
git commit -q -m "refactor(typed_graphql_codegen): keep the command line out of the library" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Fetch the schema from a URL

`SchemaFetcher` posts `IntrospectionQuery.full` to a schema URL with the configured headers (30 s timeout); every transport failure is `GQL510`, a response with errors and no data `GQL502`. `HeaderExpander` fills `${NAME}` from the environment (`GQL501` when unset or when a value injects a control character). `CodegenCommand.run` becomes asynchronous.

Commit on the branch: `014c3c2`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/cli/header_expander.dart`, `packages/typed_graphql_codegen/lib/src/cli/schema_fetch_result.dart`, `packages/typed_graphql_codegen/lib/src/cli/schema_fetcher.dart`
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart`, `packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart`, `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`, `packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart`
- Test: `packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart`, `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`, `packages/typed_graphql_codegen/test/cli/header_expander_test.dart`, `packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart`, `packages/typed_graphql_codegen/test/support/cli_project.dart`

**Interfaces:**
- Consumes: Tasks 2-3; M10a `HeaderReader`, `SchemaLocation`, `IntrospectionFileReader`; the core `IntrospectionQuery`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// cli/codegen_command.dart
final class CodegenCommand
  const CodegenCommand(
  final StringSink out
  final StringSink err
  final String workingDirectory
  final Map<String, String> environment
  final SchemaFetcher fetcher
  Future<int> run(List<String> arguments) async

// cli/header_expander.dart
final class const HeaderExpander(…)

// cli/project_reader.dart
final class ProjectReader
  const ProjectReader(
  final String directory
  final Map<String, String> environment
  final SchemaFetcher fetcher
  Future<ProjectReadResult> read(String configName) async
  Future<_SchemaOutcome> _readSchema(CodegenConfig config) async
sealed class _FileOutcome
final class _FileText extends _FileOutcome
final class _FileFailed extends _FileOutcome
sealed class _SchemaOutcome
final class _Text extends _SchemaOutcome
  final ProjectFile file
final class _Failed extends _SchemaOutcome
  final List<Diagnostic> problems

// cli/schema_fetch_result.dart
sealed class SchemaFetchResult
  const SchemaFetchResult()
final class SchemaFetched(…)
final class SchemaFetchFailed(…)

// cli/schema_fetcher.dart
final class SchemaFetcher
  const SchemaFetcher({
  final Duration timeout
  final HttpClient Function() clientFactory
  Future<SchemaFetchResult> fetch(Uri url, Map<String, String> headers) async
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,23 +11,23 @@ void main() {
   setUp(() => project = CliProject());
   tearDown(() => project.delete());
 
-  test('no command is a usage error', () {
-    expect(project.run([]), 64);
+  test('no command is a usage error', () async {
+    expect(await project.run([]), 64);
     expect(project.err.toString(), startsWith('Missing command.\nUsage:'));
   });
 
-  test('an unknown command is a usage error', () {
-    expect(project.run(['build']), 64);
+  test('an unknown command is a usage error', () async {
+    expect(await project.run(['build']), 64);
     expect(project.err.toString(), contains('Unknown command "build".'));
   });
 
-  test('an unknown option is a usage error', () {
-    expect(project.run(['generate', '--nope']), 64);
+  test('an unknown option is a usage error', () async {
+    expect(await project.run(['generate', '--nope']), 64);
     expect(project.err.toString(), contains('Could not find an option'));
   });
 
-  test('--help prints the usage and succeeds', () {
-    expect(project.run(['--help']), 0);
+  test('--help prints the usage and succeeds', () async {
+    expect(await project.run(['--help']), 0);
     expect(project.out.toString(), '${const CodegenCommandLine().usage}\n');
     expect(project.err.toString(), isEmpty);
   });
```

In `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -14,8 +14,8 @@ void main() {
 
   const generated = 'lib/user.graphql.dart';
 
-  test('generate writes the files of the goldens', () {
-    expect(project.run(['generate']), 0);
+  test('generate writes the files of the goldens', () async {
+    expect(await project.run(['generate']), 0);
     expect(project.out.toString(), 'Wrote 5 files.\n');
     for (final golden in Directory(
       'test/goldens/operations/output',
@@ -28,20 +28,20 @@ void main() {
     }
   });
 
-  test('a second generate writes nothing', () {
-    project.run(['generate']);
-    expect(project.run(['generate']), 0);
+  test('a second generate writes nothing', () async {
+    await project.run(['generate']);
+    expect(await project.run(['generate']), 0);
     expect(project.out.toString(), 'Nothing to write.\n');
   });
 
-  test('check after generate is clean', () {
-    project.run(['generate']);
-    expect(project.run(['check']), 0);
+  test('check after generate is clean', () async {
+    await project.run(['generate']);
+    expect(await project.run(['check']), 0);
     expect(project.out.toString(), 'Up to date.\n');
   });
 
-  test('check reports a missing file and writes nothing', () {
-    expect(project.run(['check']), 1);
+  test('check reports a missing file and writes nothing', () async {
+    expect(await project.run(['check']), 1);
     expect(
       project.err.toString(),
       contains(
@@ -52,10 +52,10 @@ void main() {
     expect(project.file(generated).existsSync(), isFalse);
   });
 
-  test('check reports an edited file and does not rewrite it', () {
-    project.run(['generate']);
+  test('check reports an edited file and does not rewrite it', () async {
+    await project.run(['generate']);
     project.file(generated).writeAsStringSync('// edited\n');
-    expect(project.run(['check']), 1);
+    expect(await project.run(['check']), 1);
     expect(
       project.err.toString(),
       "error GQL509: The generated file '$generated' is out of date; run "
@@ -64,56 +64,56 @@ void main() {
     expect(project.file(generated).readAsStringSync(), '// edited\n');
   });
 
-  test('a missing schema file is GQL510', () {
+  test('a missing schema file is GQL510', () async {
     project.file('schema.graphql').deleteSync();
-    expect(project.run(['generate']), 1);
+    expect(await project.run(['generate']), 1);
     expect(
       project.err.toString(),
       startsWith("error GQL510: Cannot read 'schema.graphql': "),
     );
   });
 
-  test('a missing configuration is GQL510', () {
-    expect(project.run(['generate', '--config', 'other.yaml']), 1);
+  test('a missing configuration is GQL510', () async {
+    expect(await project.run(['generate', '--config', 'other.yaml']), 1);
     expect(
       project.err.toString(),
       startsWith("error GQL510: Cannot read 'other.yaml': "),
     );
   });
 
-  test('a syntax error prints its place and excerpt', () {
+  test('a syntax error prints its place and excerpt', () async {
     project.file('lib/x.graphql').writeAsStringSync('query Q {\n');
-    expect(project.run(['generate']), 1);
+    expect(await project.run(['generate']), 1);
     expect(project.err.toString(), startsWith('lib/x.graphql:2:1: error GQL'));
     expect(project.err.toString(), contains('1 | query Q {'));
   });
 
-  test('a warning alone exits 0', () {
+  test('a warning alone exits 0', () async {
     for (final path in ['user', 'user_mutations', 'user_subscriptions']) {
       project.file('lib/$path.graphql').deleteSync();
     }
-    expect(project.run(['generate']), 0);
+    expect(await project.run(['generate']), 0);
     expect(project.err.toString(), contains('warning GQL506'));
   });
 
-  test('a document outside the glob is ignored', () {
+  test('a document outside the glob is ignored', () async {
     project.file('other/z.graphql').createSync(recursive: true);
     project.file('other/z.graphql').writeAsStringSync('query {');
-    expect(project.run(['generate']), 0);
+    expect(await project.run(['generate']), 0);
     expect(project.file('other/z.graphql.dart').existsSync(), isFalse);
   });
 
-  test('generate never deletes a stale generated file', () {
-    project.run(['generate']);
+  test('generate never deletes a stale generated file', () async {
+    await project.run(['generate']);
     project.file('lib/user_mutations.graphql').deleteSync();
-    expect(project.run(['generate']), 0);
+    expect(await project.run(['generate']), 0);
     expect(
       project.file('lib/user_mutations.graphql.dart').existsSync(),
       isTrue,
     );
   });
 
-  test('the executable passes the exit code to the process', () {
+  test('the executable passes the exit code to the process', () async {
     final result = Process.runSync(Platform.resolvedExecutable, [
       'run',
       '${Directory.current.path}/bin/typed_graphql_codegen.dart',
```

Create `packages/typed_graphql_codegen/test/cli/header_expander_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/cli/header_expander.dart';

void main() {
  const expander = HeaderExpander({'A': 'one', 'B': 'a\nb'});

  test('replaces every reference', () {
    final result = expander.expand({'X': r'${A}-${A}'});
    expect(result.headers, {'X': 'one-one'});
    expect(result.problems, isEmpty);
  });

  test('keeps a lone dollar, a double dollar and an unclosed brace', () {
    final result = expander.expand({'X': r'$ $$ ${A'});
    expect(result.headers, {'X': r'$ $$ ${A'});
  });

  test('a missing variable is GQL501 and drops the header', () {
    final result = expander.expand({'X': r'${NOPE}'});
    expect(result.headers, isEmpty);
    expect(result.problems.map((d) => d.toString()), [
      "error GQL501: The header 'X' uses the environment variable 'NOPE', "
          'which is not set.',
    ]);
  });

  test('a line break from the environment is GQL501', () {
    final result = expander.expand({'X': r'${B}'});
    expect(result.headers, isEmpty);
    expect(result.problems.map((d) => d.toString()), [
      "error GQL501: The value of header 'X' must not have a control "
          'character after its environment variables are expanded.',
    ]);
  });
}
```

Create `packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/cli/schema_fetcher.dart';

import '../support/cli_project.dart';

void main() {
  Schema schemaOf(String sdl) {
    final source = Source(sdl, name: 'schema.graphql');
    final document = (const Parser().parse(source) as ParseSuccess).document;
    final built = const SchemaBuilder().fromSdl(document, source: source);
    return (built as BuildSuccess).schema;
  }

  // The golden configuration's other settings, so the output is the same.
  String keptSettings(CliProject project) {
    final lines = project.file('typed_graphql.yaml').readAsLinesSync();
    return '${lines.skip(1).join('\n')}\n';
  }

  late CliProject project;
  late HttpServer server;
  late List<({HttpHeaders headers, String body})> requests;
  void Function(HttpResponse) respond = (response) {};

  setUp(() async {
    project = CliProject();
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      requests.add((headers: request.headers, body: body));
      respond(request.response);
    });
    final sdl = project.file('schema.graphql').readAsStringSync();
    final schema = schemaOf(sdl);
    respond = (response) {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'data': schema.toIntrospection().toJson()}));
      response.close();
    };
    project
        .file('typed_graphql.yaml')
        .writeAsStringSync(
          'schema: http://127.0.0.1:${server.port}/graphql\n'
          'headers:\n'
          '  Authorization: Bearer \${TOKEN}\n'
          '${keptSettings(project)}',
        );
  });
  tearDown(() async {
    await server.close(force: true);
    project.delete();
  });

  const environment = {'TOKEN': 'secret-token-value'};

  test('generate from a URL writes the files of the SDL project', () async {
    expect(await project.run(['generate'], environment: environment), 0);
    expect(project.out.toString(), 'Wrote 5 files.\n');
    expect(project.file('lib/user.graphql.dart').existsSync(), isTrue);
  });

  test('the request carries the expanded header and the query', () async {
    await project.run(['generate'], environment: environment);
    expect(
      requests.single.headers.value('authorization'),
      startsWith('Bearer'),
    );
    expect(
      requests.single.headers.value('authorization'),
      'Bearer secret-token-value',
    );
    expect(requests.single.headers.contentType?.mimeType, 'application/json');
    expect(
      requests.single.body,
      GraphQLRequest(query: IntrospectionQuery.full.text).toJson().toString(),
    );
  });

  test('a 401 is GQL510 with the status', () async {
    respond = (response) {
      response.statusCode = 401;
      response.write('nope');
      response.close();
    };
    expect(await project.run(['generate'], environment: environment), 1);
    expect(
      project.err.toString(),
      'error GQL510: Cannot fetch the schema from '
      "'http://127.0.0.1:${server.port}/graphql': HTTP 401 Unauthorized: "
      'nope.\n',
    );
  });

  test('a closed port is GQL510', () async {
    final port = server.port;
    await server.close(force: true);
    expect(await project.run(['generate'], environment: environment), 1);
    expect(
      project.err.toString(),
      startsWith(
        'error GQL510: Cannot fetch the schema from '
        "'http://127.0.0.1:$port/graphql': ",
      ),
    );
  });

  test('a slow server past the timeout is GQL510', () async {
    final hold = Completer<void>();
    respond = (response) {
      unawaited(hold.future.then((_) => response.close()));
    };
    final code = await project.run(
      ['generate'],
      environment: environment,
      fetcher: const SchemaFetcher(timeout: Duration(milliseconds: 200)),
    );
    hold.complete();
    expect(code, 1);
    expect(
      project.err.toString(),
      'error GQL510: Cannot fetch the schema from '
      "'http://127.0.0.1:${server.port}/graphql': "
      'the request timed out after 200ms.\n',
    );
  });

  test('errors without data are GQL502', () async {
    respond = (response) {
      response.write(
        jsonEncode({
          'errors': [
            {'message': 'Introspection is disabled'},
          ],
        }),
      );
      response.close();
    };
    expect(await project.run(['generate'], environment: environment), 1);
    expect(project.err.toString(), contains('error GQL502: The server '));
    expect(project.err.toString(), contains('Introspection is disabled'));
  });

  test('a missing environment variable is GQL501 and sends nothing', () async {
    expect(await project.run(['generate']), 1);
    expect(
      project.err.toString(),
      "error GQL501: The header 'Authorization' uses the environment "
      "variable 'TOKEN', which is not set.\n",
    );
    expect(requests, isEmpty);
  });

  test('a header value never appears in the output', () async {
    respond = (response) {
      response.statusCode = 500;
      response.close();
    };
    await project.run(['generate'], environment: environment);
    await project.run(['check'], environment: environment);
    expect(
      project.out.toString() + project.err.toString(),
      isNot(contains('secret-token-value')),
    );
  });
}
```

In `packages/typed_graphql_codegen/test/support/cli_project.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'dart:io';
 
 import 'package:typed_graphql_codegen/src/cli/codegen_command.dart';
+import 'package:typed_graphql_codegen/src/cli/schema_fetcher.dart';
 
 /// A temporary project copied from the `operations` golden input, and the
 /// way to run the command line in it.
@@ -29,10 +30,20 @@ final class CliProject {
   final StringBuffer err = StringBuffer();
 
   /// Runs [arguments] in the project; returns the exit code.
-  int run(List<String> arguments) {
+  Future<int> run(
+    List<String> arguments, {
+    Map<String, String> environment = const {},
+    SchemaFetcher fetcher = const SchemaFetcher(),
+  }) {
     out.clear();
     err.clear();
-    return CodegenCommand(out, err, directory.path).run(arguments);
+    return CodegenCommand(
+      out,
+      err,
+      directory.path,
+      environment: environment,
+      fetcher: fetcher,
+    ).run(arguments);
   }
 
   /// The file at [path], relative to the project.
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_line_test.dart test/cli/codegen_command_test.dart test/cli/header_expander_test.dart test/cli/schema_fetcher_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,10 +2,11 @@ import 'dart:io';
 
 import 'package:typed_graphql_codegen/src/cli/codegen_command.dart';
 
-void main(List<String> arguments) {
-  exitCode = CodegenCommand(
+Future<void> main(List<String> arguments) async {
+  exitCode = await CodegenCommand(
     stdout,
     stderr,
     Directory.current.path,
+    environment: Platform.environment,
   ).run(arguments);
 }
```

In `packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,29 +8,44 @@ import 'diagnostic_printer.dart';
 import 'output_writer.dart';
 import 'project_read_result.dart';
 import 'project_reader.dart';
+import 'schema_fetcher.dart';
 
 /// Runs the code generator's command line, with injected streams and working
 /// directory so tests run it in process.
 ///
 /// {@category codegen}
-final class const CodegenCommand(
+final class CodegenCommand {
+  /// Creates a command that writes to [out] and [err]; [environment] feeds
+  /// the `${NAME}` references of the headers (`bin/` passes the process's)
+  /// and [fetcher] gets a schema URL.
+  const CodegenCommand(
+    this.out,
+    this.err,
+    this.workingDirectory, {
+    this.environment = const {},
+    this.fetcher = const SchemaFetcher(),
+  });
+
   /// Where normal output goes.
-  final StringSink out,
+  final StringSink out;
 
   /// Where diagnostics and usage errors go.
-  final StringSink err,
+  final StringSink err;
 
   /// The directory relative `--config` paths are resolved against.
-  final String workingDirectory,
-) {
-  /// Creates a command that writes to [out] and [err].
-  this;
+  final String workingDirectory;
+
+  /// The environment variables the header values may reference.
+  final Map<String, String> environment;
+
+  /// What fetches a schema URL.
+  final SchemaFetcher fetcher;
 
   /// The exit code of a usage error.
   static const int usageExitCode = 64;
 
   /// Runs [arguments]; returns the process exit code.
-  int run(List<String> arguments) {
+  Future<int> run(List<String> arguments) async {
     const commandLine = CodegenCommandLine();
     switch (commandLine.parse(arguments)) {
       case CommandLineHelp():
@@ -41,14 +56,21 @@ final class const CodegenCommand(
         err.writeln(commandLine.usage);
         return usageExitCode;
       case CommandLineRun(:final isCheck, :final configPath):
-        return _run(isCheck: isCheck, configPath: configPath);
+        return await _run(isCheck: isCheck, configPath: configPath);
     }
   }
 
-  int _run({required bool isCheck, required String configPath}) {
+  Future<int> _run({
+    required bool isCheck,
+    required String configPath,
+  }) async {
     final absolute = p.normalize(p.absolute(workingDirectory, configPath));
     final directory = p.dirname(absolute);
-    final project = ProjectReader(directory).read(p.basename(absolute));
+    final project = await ProjectReader(
+      directory,
+      environment: environment,
+      fetcher: fetcher,
+    ).read(p.basename(absolute));
     if (project is! ProjectRead) {
       return _report((project as ProjectReadFailed).diagnostics);
     }
```

Create `packages/typed_graphql_codegen/lib/src/cli/header_expander.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Replaces `${NAME}` in header values by environment variables.
///
/// Only the exact form `${NAME}` with `NAME` of `[A-Za-z_][A-Za-z0-9_]*` is a
/// reference; `$$`, a lone `$` and a `${` without `}` stay as written, so
/// there is no escape syntax. A value is expanded once: the text an
/// environment variable holds is not expanded again.
///
/// {@category codegen}
final class const HeaderExpander(
  /// The environment variables by name.
  final Map<String, String> environment,
) {
  /// Creates an expander over [environment].
  this;

  static final RegExp _reference = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
  static final RegExp _control = RegExp(r'[\x00-\x08\x0A-\x1F\x7F]');

  /// Expands every value of [headers]; the problems (`GQL501`) never hold a
  /// header value, and a header with a problem is left out of the result.
  ({Map<String, String> headers, List<Diagnostic> problems}) expand(
    Map<String, String> headers,
  ) {
    final expanded = <String, String>{};
    final problems = <Diagnostic>[];
    for (final MapEntry(:key, :value) in headers.entries) {
      final missing = _missing(value);
      if (missing != null) {
        problems.add(
          _problem(
            "The header '$key' uses the environment variable '$missing', "
            'which is not set.',
          ),
        );
        continue;
      }
      final text = value.replaceAllMapped(
        _reference,
        (match) => environment[match.group(1)]!,
      );
      if (_control.hasMatch(text)) {
        problems.add(
          _problem(
            "The value of header '$key' must not have a control character "
            'after its environment variables are expanded.',
          ),
        );
        continue;
      }
      expanded[key] = text;
    }
    return (headers: expanded, problems: problems);
  }

  String? _missing(String value) {
    for (final match in _reference.allMatches(value)) {
      final name = match.group(1)!;
      if (!environment.containsKey(name)) return name;
    }
    return null;
  }

  Diagnostic _problem(String message) =>
      Diagnostic(.invalidConfig, .error, message);
}
```

In `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,61 +9,81 @@ import '../config/codegen_config.dart';
 import '../config/config_result.dart';
 import '../config/schema_location.dart';
 import '../project/project_file.dart';
+import 'header_expander.dart';
 import 'project_read_result.dart';
+import 'schema_fetch_result.dart';
+import 'schema_fetcher.dart';
 
 /// Reads the configuration, the schema file and the documents of a project
 /// from disk.
 ///
 /// {@category codegen}
-final class const ProjectReader(
+final class ProjectReader {
+  /// Creates a reader for the project in [directory]; [environment] feeds the
+  /// `${NAME}` references of the headers and [fetcher] gets a schema URL.
+  const ProjectReader(
+    this.directory, {
+    this.environment = const {},
+    this.fetcher = const SchemaFetcher(),
+  });
+
   /// The directory of the configuration file; every path is relative to it.
-  final String directory,
-) {
-  /// Creates a reader for the project in [directory].
-  this;
+  final String directory;
+
+  /// The environment variables the header values may reference.
+  final Map<String, String> environment;
+
+  /// What fetches the schema of a configuration with a `schema` URL.
+  final SchemaFetcher fetcher;
 
   /// Reads the project whose configuration is the file [configName].
-  ProjectReadResult read(String configName) {
+  Future<ProjectReadResult> read(String configName) async {
     final configText = _readText(configName);
-    if (configText is _Failed) return ProjectReadFailed([configText.problem]);
-    final parsed = CodegenConfig.parse(
-      (configText as _Text).text,
-      path: configName,
-    );
+    if (configText is! _FileText) {
+      return ProjectReadFailed([(configText as _FileFailed).problem]);
+    }
+    final parsed = CodegenConfig.parse(configText.text, path: configName);
     if (parsed is ConfigFailure) return ProjectReadFailed(parsed.diagnostics);
     final config = (parsed as ConfigSuccess).config;
-    final location = config.schema;
-    if (location is! SchemaFile) {
-      return ProjectReadFailed([
-        _unreadable(
-          '${location is SchemaUrl ? location.url : location}',
-          'Fetching a schema URL is not supported here.',
-        ),
-      ]);
+    final schema = await _readSchema(config);
+    return switch (schema) {
+      _Text(:final file) => _readSources(config, file),
+      _Failed(:final problems) => ProjectReadFailed(problems),
+    };
+  }
+
+  Future<_SchemaOutcome> _readSchema(CodegenConfig config) async {
+    switch (config.schema) {
+      case SchemaFile(:final path):
+        final text = _readText(path);
+        return switch (text) {
+          _FileText() => _Text(ProjectFile(path, text.text)),
+          _FileFailed() => _Failed([text.problem]),
+        };
+      case SchemaUrl(:final url):
+        final expansion = HeaderExpander(environment).expand(config.headers);
+        if (expansion.problems.isNotEmpty) return _Failed(expansion.problems);
+        return switch (await fetcher.fetch(url, expansion.headers)) {
+          SchemaFetched(:final file) => _Text(file),
+          SchemaFetchFailed(:final diagnostic) => _Failed([diagnostic]),
+        };
     }
-    return _readSources(config, location.path);
   }
 
-  ProjectReadResult _readSources(CodegenConfig config, String schemaPath) {
-    final schema = _readText(schemaPath);
-    if (schema is _Failed) return ProjectReadFailed([schema.problem]);
+  ProjectReadResult _readSources(CodegenConfig config, ProjectFile schema) {
     final problems = <Diagnostic>[];
     final documents = <ProjectFile>[];
-    for (final path in _documentPaths(config, schemaPath)) {
+    for (final path in _documentPaths(config, schema.path)) {
       final text = _readText(path);
       switch (text) {
-        case _Text():
+        case _FileText():
           documents.add(ProjectFile(path, text.text));
-        case _Failed():
+        case _FileFailed():
           problems.add(text.problem);
       }
     }
     if (problems.isNotEmpty) return ProjectReadFailed(problems);
-    return ProjectRead(
-      config,
-      ProjectFile(schemaPath, (schema as _Text).text),
-      documents,
-    );
+    return ProjectRead(config, schema, documents);
   }
 
   List<String> _documentPaths(CodegenConfig config, String schemaPath) {
@@ -80,15 +100,15 @@ final class const ProjectReader(
     return paths.toList()..sort();
   }
 
-  _ReadOutcome _readText(String path) {
+  _FileOutcome _readText(String path) {
     try {
-      return _Text(File(p.join(directory, path)).readAsStringSync());
+      return _FileText(File(p.join(directory, path)).readAsStringSync());
     } on FileSystemException catch (error) {
-      return _Failed(
+      return _FileFailed(
         _unreadable(path, error.osError?.message ?? error.message),
       );
     } on FormatException catch (error) {
-      return _Failed(_unreadable(path, error.message));
+      return _FileFailed(_unreadable(path, error.message));
     }
   }
 
@@ -99,16 +119,30 @@ final class const ProjectReader(
   );
 }
 
-sealed class _ReadOutcome {
-  const _ReadOutcome();
+sealed class _FileOutcome {
+  const _FileOutcome();
 }
 
-final class _Text extends _ReadOutcome {
-  const _Text(this.text);
+final class _FileText extends _FileOutcome {
+  const _FileText(this.text);
   final String text;
 }
 
-final class _Failed extends _ReadOutcome {
-  const _Failed(this.problem);
+final class _FileFailed extends _FileOutcome {
+  const _FileFailed(this.problem);
   final Diagnostic problem;
 }
+
+sealed class _SchemaOutcome {
+  const _SchemaOutcome();
+}
+
+final class _Text extends _SchemaOutcome {
+  const _Text(this.file);
+  final ProjectFile file;
+}
+
+final class _Failed extends _SchemaOutcome {
+  const _Failed(this.problems);
+  final List<Diagnostic> problems;
+}
```

Create `packages/typed_graphql_codegen/lib/src/cli/schema_fetch_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';

/// What [SchemaFetcher] got from a schema URL.
///
/// {@category codegen}
sealed class SchemaFetchResult {
  const SchemaFetchResult();
}

/// The server answered with a 2xx status.
///
/// {@category codegen}
final class SchemaFetched(
  /// The response body, at the path `'<url>.json'` so that the engine reads
  /// it as an introspection result.
  final ProjectFile file,
) extends SchemaFetchResult {
  /// Creates the result.
  this;
}

/// The schema could not be fetched.
///
/// {@category codegen}
final class SchemaFetchFailed(
  /// The `GQL510` that says why; it never holds a header value.
  final Diagnostic diagnostic,
) extends SchemaFetchResult {
  /// Creates the result.
  this;
}
```

Create `packages/typed_graphql_codegen/lib/src/cli/schema_fetcher.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';
import 'schema_fetch_result.dart';

/// Fetches a schema by posting the full introspection query to a URL.
///
/// {@category codegen}
final class SchemaFetcher {
  /// Creates a fetcher; [timeout] bounds the whole exchange, and
  /// [clientFactory] makes the HTTP client (tests inject their own).
  const SchemaFetcher({
    this.timeout = const Duration(seconds: 30),
    this.clientFactory = HttpClient.new,
  });

  /// How long the request, the response and the body may take together.
  final Duration timeout;

  /// Makes the client of one fetch; the fetcher closes it.
  final HttpClient Function() clientFactory;

  static const int _bodyExcerptLength = 200;

  /// Posts the introspection query to [url] with [headers]; never throws.
  Future<SchemaFetchResult> fetch(Uri url, Map<String, String> headers) async {
    final client = clientFactory();
    try {
      return await _exchange(client, url, headers).timeout(timeout);
    } on TimeoutException {
      final limit = timeout.inMilliseconds % 1000 == 0
          ? '${timeout.inSeconds}s'
          : '${timeout.inMilliseconds}ms';
      return _failed(url, 'the request timed out after $limit');
    } on IOException catch (error) {
      return _failed(url, _describe(error));
    } on FormatException {
      return _failed(url, 'the response is not valid UTF-8');
    } finally {
      client.close(force: true);
    }
  }

  Future<SchemaFetchResult> _exchange(
    HttpClient client,
    Uri url,
    Map<String, String> headers,
  ) async {
    final request = await client.postUrl(url);
    request.headers
      ..contentType = ContentType.json
      ..set(
        HttpHeaders.acceptHeader,
        'application/graphql-response+json, application/json',
      );
    for (final MapEntry(:key, :value) in headers.entries) {
      request.headers.set(key, value);
    }
    request.add(utf8.encode(_body));
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode > 299) {
      final excerpt = text.length > _bodyExcerptLength
          ? text.substring(0, _bodyExcerptLength)
          : text;
      final status = '${response.statusCode} ${response.reasonPhrase}';
      return _failed(url, 'HTTP $status: $excerpt');
    }
    return SchemaFetched(ProjectFile('$url.json', text));
  }

  String get _body => GraphQLRequest(
    query: IntrospectionQuery.full.text,
  ).toJson().toString();

  String _describe(IOException error) => switch (error) {
    SocketException(:final message) => message,
    HttpException(:final message) => message,
    _ => error.toString(),
  };

  SchemaFetchFailed _failed(Uri url, String reason) => SchemaFetchFailed(
    Diagnostic(
      .inputUnreadable,
      .error,
      "Cannot fetch the schema from '$url': $reason.",
    ),
  );
}
```

In `packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -25,6 +25,14 @@ final class const IntrospectionFileReader() {
   BuildResult _build(JsonObject object, SourceSpan place) {
     // A raw HTTP response wraps the result in `data`.
     final data = object['data'];
+    final answer = _errorMessage(object);
+    if (data is! JsonObject && answer != null) {
+      return _failure(
+        'The server answered the introspection query with errors and no '
+        'data: $answer',
+        place,
+      );
+    }
     final result = const SchemaBuilder(
       includesDeferAndStream: true,
     ).fromIntrospection(data is JsonObject ? data : object);
@@ -37,6 +45,14 @@ final class const IntrospectionFileReader() {
     };
   }
 
+  // The first message of a GraphQL response's `errors`, if it has one.
+  String? _errorMessage(JsonObject object) {
+    if (object['errors'] case JsonArray(items: [final JsonObject first, ...])) {
+      if (first['message'] case JsonString(:final value)) return value;
+    }
+    return null;
+  }
+
   BuildResult _failure(String message, SourceSpan place) => BuildFailure(
     Schema(),
     [Diagnostic(.invalidSchemaInput, .error, message, span: place)],
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_line_test.dart test/cli/codegen_command_test.dart test/cli/header_expander_test.dart test/cli/schema_fetcher_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql_codegen/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -74,4 +74,10 @@
 - `dart run typed_graphql_codegen generate` writes the generated files and
   `check` fails when one is missing or out of date (`GQL509`); a file the
   command cannot read is `GQL510`. `--config` names the configuration file.
-  `generate` never deletes a file. `CodegenCommand` runs both in process.
+  `generate` never deletes a file. `CodegenCommand` (in `src/cli/`, not exported: it imports `dart:io`) runs
+  both in process.
+- A `schema:` URL is fetched with a POST of the full introspection query
+  (`SchemaFetcher`, 30 s timeout); a failure is `GQL510` with the status, and
+  a response with `errors` and no `data` is `GQL502`. Header values may use
+  `${NAME}` (`HeaderExpander`): a variable that is not set is `GQL501`, a line
+  break from a variable is refused, and no header value is ever printed.
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/bin/typed_graphql_codegen.dart packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart packages/typed_graphql_codegen/lib/src/cli/header_expander.dart packages/typed_graphql_codegen/lib/src/cli/project_reader.dart packages/typed_graphql_codegen/lib/src/cli/schema_fetch_result.dart packages/typed_graphql_codegen/lib/src/cli/schema_fetcher.dart packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart packages/typed_graphql_codegen/test/cli/codegen_command_line_test.dart packages/typed_graphql_codegen/test/cli/codegen_command_test.dart packages/typed_graphql_codegen/test/cli/header_expander_test.dart packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart packages/typed_graphql_codegen/test/support/cli_project.dart
git commit -q -m "feat(typed_graphql_codegen): fetch the schema from a URL" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Document the CLI and add the example

The guide's Command line section and the complete diagnostics table, the README quick start, the checked-in example project (a workspace member with its own `pubspec.yaml`, because the generated code imports the client) with a byte-for-byte test, the "Dart GraphQL code generator" discovery query, `llms.txt`, the `CLAUDE.md` Codegen paragraph and the handoff row.

Commit on the branch: `1b898b7`.

**Files:**
- Create: `packages/typed_graphql_codegen/example/README.md`, `packages/typed_graphql_codegen/example/lib/schema.graphql.dart`, `packages/typed_graphql_codegen/example/lib/user.graphql`, `packages/typed_graphql_codegen/example/lib/user.graphql.dart`, `packages/typed_graphql_codegen/example/pubspec.yaml`, `packages/typed_graphql_codegen/example/schema.graphql`, `packages/typed_graphql_codegen/example/typed_graphql.yaml`
- Modify: `CLAUDE.md`, `docs/discovery.md`, `docs/superpowers/HANDOFF.md`, `llms.txt`, `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/README.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`, `pubspec.yaml`
- Test: `packages/typed_graphql_codegen/test/example_test.dart`

**Interfaces:**
- Consumes: Tasks 1-4 and M10a-M10c.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/example_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main() {
  const root = 'example';
  String read(String path) => File('$root/$path').readAsStringSync();

  final parsed = CodegenConfig.parse(
    read('typed_graphql.yaml'),
    path: 'typed_graphql.yaml',
  );
  final config = (parsed as ConfigSuccess).config;
  final result = ClientGenerator(config).generate(
    schema: ProjectFile('schema.graphql', read('schema.graphql')),
    documents: [ProjectFile('lib/user.graphql', read('lib/user.graphql'))],
  );

  test('the example generates without diagnostics', () {
    expect(result.diagnostics, isEmpty);
  });

  test('the generated files are the two checked in', () {
    expect(
      [for (final file in result.files) file.path],
      ['lib/schema.graphql.dart', 'lib/user.graphql.dart'],
    );
  });

  for (final file in result.files) {
    test('${file.path} equals the checked-in file', () {
      expect(file.text, read(file.path));
    });
  }
}
```

- [ ] **Step 2: Update the package files**

In `pubspec.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,5 +16,6 @@ workspace:
   - packages/typed_graphql_shelf
   - packages/typed_graphql_client
   - packages/typed_graphql_codegen
+  - packages/typed_graphql_codegen/example
   - packages/typed_graphql_builder
   - packages/typed_graphql_conformance
```

- [ ] **Step 3: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -42,7 +42,15 @@ guide. M4b (limits and cost) delivers the opt-in limit rules (depth, aliases,
 directives, introspection: `GQL232`-`GQL236`), `recommendedRules`, the IBM
 cost directives (`includesCostDirectives`, `GQL156`-`GQL161`), `CostAnalysis`,
 `SlicingArgumentsRule` and `MaxCostRule` (`GQL237`, `GQL238`), the operation
-fuzzers and the guide sections on limits and cost.
+fuzzers and the guide sections on limits and cost. M10 (client code
+generation) delivers the `typed_graphql.yaml` reader, schema loading from a
+file or a URL, the project's documents as one fragment graph, the planner and
+emitters that generate the schema-types library and a library per document
+(operations, variables, data, fragments, sealed polymorphic classes, the
+minified document with its SHA-256, the persisted-operations manifest), the
+codes `GQL500`-`GQL511`, the `generate` and `check` command line, `Optional`
+in the core, the generated-code contract in `typed_graphql_client`, the goldens
+and the Client Code Generation guide.
 
 ## Documents
 
@@ -388,6 +396,58 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `MaxCostRule` (`GQL238`) and `SlicingArgumentsRule` (`GQL237`) are
   opt-in rules.
 
+**Codegen** (`packages/typed_graphql_codegen`; M10). Depends on the core,
+`args`, `crypto`, `glob`, `path` and `yaml`, never on `analyzer`; the engine
+reads no file: it takes `ProjectFile`s (path and text) and returns diagnostics
+and `GeneratedFile`s.
+- `config/`: `CodegenConfig.parse` reads `typed_graphql.yaml` into the sealed
+  `ConfigResult` (`GQL500` YAML syntax, `GQL501` a missing, unknown or mistyped
+  key or a malformed path or Dart reference); `SchemaLocation` (file or URL),
+  `ScalarMapping` and `DartReference` (`<library>#<Name>`). `headers` stay as
+  written; `${NAME}` is expanded by the CLI.
+- `schema/`: `SchemaLoader` builds a `ValidSchema` from SDL or, for a `.json`
+  path, an introspection result (`GQL502`).
+- `documents/`: `ProjectDocuments` parses every file and validates them as one
+  fragment graph; `ProjectSourceMap` maps a node of the merged graph back to
+  its file, line and column.
+- `generator/`: `ClientGenerator(config)` has `rules` (the specified rules
+  minus the unused-fragment and lone-anonymous ones, plus `GQL503` named
+  operations, `GQL504` unsupported `@defer`/`@stream`/`__schema`/`__type` and
+  a subscription whose root fragment becomes a sealed class, and `GQL506` no
+  document as a warning), `check` and `generate` (`GenerationResult`: diagnostics
+  and files; an error means no files). It also checks the scalar mappings
+  (`GQL505`), the names (`GQL507` a Dart name declared twice, also members
+  and paths; `GQL508` a name that hides a Dart type the code uses) and the
+  size (`GQL511`, 10000 classes per operation or fragment).
+- `plan/`: the planner turns a validated selection into `PlannedClass`es
+  without emitting text. `FieldCollector` merges the fields of a selection
+  with the fragments and conditions that apply; `Applicability` decides, per
+  possible type, whether an inline or spread fragment applies; `ShapePlanner`
+  builds the data classes, and the variant rules: a selection on an abstract
+  type that tells types apart is a sealed base, a final class per type and
+  an unknown one; a base declares a field only when its class is the same in
+  every variant, and a field a variant re-selects with more is dropped from
+  the base.
+- `emit/`: `DartWriter` (indentation, fenced doc comments, wrapped calls),
+  `DartNames` (Dart members and classes from GraphQL names), `Imports`,
+  `TypeMapper` (GraphQL type to Dart type and codec), and one emitter per
+  kind of class (enum, input and `@oneOf` input, operation, variables, data,
+  polymorphic base, fragment holder). Each class declares its own private
+  codecs; output is deterministic and sorted.
+- `cli/` (the only `dart:io` user, not exported from the barrel; `bin/` runs
+  `CodegenCommand`): `ProjectReader` (async; reads the files, `SchemaFetcher`
+  posts the introspection query to a URL, `HeaderExpander` expands
+  `${NAME}`), `OutputWriter` (writes only changed files, never deletes;
+  `outdated` is `GQL509`), `DiagnosticPrinter`. `GQL510` is an unreadable
+  input; exit codes 0, 1, 64.
+- Tests: `test/goldens/<case>/{input,output,support}` hold the inputs and the
+  expected generated files (`UPDATE_GOLDENS=1 dart test test/golden_test.dart`
+  rewrites them); `generated_code_test.dart` analyzes and runs the goldens in
+  a temporary package (tag `analysis`, skipped under `--compiler exe`);
+  `test/example_test.dart` generates `example/` again and compares it byte for
+  byte. `example/` is a workspace member with its own `pubspec.yaml`
+  (`publish_to: none`) because the generated code imports the client.
+
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
 `ArgumentError`, `RangeError`, `StateError`.
@@ -595,4 +655,8 @@ README that leaves the package folder is an absolute URL.
   introspection, coordinates, valid operations, hostile operations and
   hostile shapes); `TYPED_GRAPHQL_FUZZ_ITERATIONS` and
   `TYPED_GRAPHQL_FUZZ_SEED` tune them.
+- Codegen goldens: `packages/typed_graphql_codegen/test/goldens/`, with the
+  runner `test/golden_test.dart` and the case loader
+  `test/support/golden_case.dart`; the checked-in example project is
+  `packages/typed_graphql_codegen/example/`.
 - CI: `.github/workflows/ci.yml`.
```

In `docs/discovery.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -41,7 +41,7 @@ adds its row (or turns it to "yes") together with its README line and its
 | limit GraphQL query depth or cost dart | M4 | yes |
 | execute a GraphQL query dart | M5 | no |
 | GraphQL server dart | M7 | no |
-| generate a typed GraphQL client dart | M10 | no |
+| generate a typed GraphQL client dart | M10 | yes |
 
 ## Metadata
 
```

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,6 +16,7 @@ needed.
 | M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
+| M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | — | M10 is done on branch `m10-final`, not merged and not pushed (the plans are generated from the commits). `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
 
 **Decisions (2026-10-14):**
 - Layer order is diagnostics < language < protocol < schema < validation; the
```

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,7 +7,7 @@
 - [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, operation validation with opt-in limits and cost analysis, wire protocol and diagnostics
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
-- [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; reads typed_graphql.yaml, checks a project's schema and .graphql documents, and generates the schema types and the operation and fragment classes of each document, no CLI yet (M8, M10)
+- [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; the CLI `dart run typed_graphql_codegen generate|check` reads typed_graphql.yaml, loads the schema from a file or a URL, validates the .graphql documents and generates the schema types and the operation and fragment classes of each document; the generated code needs typed_graphql_client, which holds only its contract until M11 (the server generator is M8)
 - [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): skeleton; typed schema builder, executor and transport handlers, not usable yet (M5 to M7)
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
```

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- The command line `dart run typed_graphql_codegen generate|check [--config]`:
  `generate` writes the changed files and never deletes; `check` reports
  `GQL509` for a missing or outdated file; exit codes 0, 1 and 64; unreadable
  inputs are `GQL510`.
- A `schema` URL is fetched with the full introspection query; `${NAME}` in
  `headers` is read from the environment and values are never printed.
- The README's quick start, the guide's "Command line" section and the
  `example/` project with its generated code checked in
  (`test/example_test.dart`).
```

In `packages/typed_graphql_codegen/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -4,20 +4,35 @@
 ![Role](https://img.shields.io/badge/role-codegen-blue)
 ![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)
 
-**Check a GraphQL project for Dart client code generation: read `typed_graphql.yaml`, load the schema and validate the `.graphql` operations, with every problem reported at its file, line and column.** It generates the library of the enums and input objects the operations use and, per document, the classes of its operations, variables, data and fragments, with the minified document, its SHA-256 and the persisted-operations manifest. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
-
-> **Status: under construction.** This release reads the project's
-> configuration, `typed_graphql.yaml` (`CodegenConfig`), and checks a project:
-> `ClientGenerator.check` loads the schema, parses and validates the
-> `.graphql` documents as one fragment graph, and reports every problem with
-> its file, line and column. `ClientGenerator.generate` also writes the
-> schema-types library and a library per document; the CLI arrives in M10 and the SDL-first server generator in M8 (see the
+**Generate typed Dart client code from a GraphQL schema and `.graphql` operations, from the command line or in code, with every problem reported at its file, line and column.** It reads `typed_graphql.yaml`, loads the schema from a file or a URL, validates the documents and writes the library of the enums and input objects the operations use and, per document, the classes of its operations, variables, data and fragments, with the minified document, its SHA-256 and the persisted-operations manifest. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
+
+> **Status: under construction.** The client generator and its command line
+> work; the classes need `typed_graphql_client`, which holds only the contract
+> the generated code compiles against until M11. The SDL-first server
+> generator (M8) and the `build_runner` builder (M9) are not built yet (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
+Quick start. Write `typed_graphql.yaml` next to your `pubspec.yaml`:
+
+```yaml
+schema: schema.graphql
+documents: lib/**.graphql
+```
+
+Then run it; `check` exits with 1 when a generated file is out of date:
+
+```sh
+dart run typed_graphql_codegen generate
+dart run typed_graphql_codegen check
+```
+
 It does not depend on `analyzer`. The
 [Client Code Generation guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/doc/client_codegen.md)
-lists the configuration keys, shows a check and a generation, describes the generated enums, input objects, scalars, operations and fragments, and lists the codes `GQL500` to
-`GQL508`.
+lists the configuration keys, the command line and its exit codes, describes
+the generated enums, input objects, scalars, operations and fragments, and
+lists the codes `GQL500` to `GQL511`. The
+[example](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql_codegen/example)
+is a small project with its generated code checked in.
 
 ## License
 
````

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -7,9 +7,11 @@ and reports each problem as a diagnostic at `file:line:column`. It generates
 the schema-types library (the enums and input objects the documents use,
 with the scalars mapped to Dart types) and a library per document: the
 classes of its operations, variables, data and fragments, the minified
-document with its SHA-256, and the persisted-operations manifest. The command
-line arrives next. Bad input never throws: a problem is a diagnostic with a
-stable code, in a sealed result or a list.
+document with its SHA-256, and the persisted-operations manifest. The
+command line (`generate` and `check`) reads the project from disk, takes the
+schema from a file or a URL and writes the generated files. Bad input never
+throws: a problem is a diagnostic with a stable code, in a sealed result or a
+list.
 
 ## Configuration
 
@@ -50,7 +52,7 @@ headers:
 ```
 
 The values of `headers` are kept as written: the configuration reader does
-not expand `${NAME}`.
+not expand `${NAME}`; the command line does (see "Command line").
 
 ## Checking a project
 
@@ -162,6 +164,59 @@ lib/schema.graphql.dart: Role, RoleUnknown
 role.graphql.dart: GetRoleQuery, GetRoleData
 ```
 
+## Command line
+
+The same engine runs from a terminal, in the folder of the project:
+
+```text
+dart run typed_graphql_codegen generate
+dart run typed_graphql_codegen check
+dart run typed_graphql_codegen generate --config path/to/typed_graphql.yaml
+```
+
+`--config` (`-c`) names the configuration file; it defaults to
+`typed_graphql.yaml` in the working directory, and every path in it is
+relative to the file's folder. `--help` prints the usage.
+
+`generate` reads the configuration, the schema and the documents, runs the
+checks and, when there is no error, writes each generated file whose text
+differs from what is on disk (creating folders as needed). It prints
+`Wrote N files.` or `Nothing to write.` and never deletes a file: a library
+whose document you removed stays until you delete it. `check` writes nothing;
+it reports a `GQL509` for each generated file that is missing or differs, and
+prints `Up to date.` when none does, so a CI job can run it to catch generated
+code that was not regenerated. Nothing is written when a document has an
+error, and an error in one file blocks every file.
+
+A diagnostic is printed to the error stream as
+`path:line:column: severity GQLnnn: message`, followed by the excerpt of its
+place; one without a place has no path. A file the command must read (the
+configuration, the schema, a document) that cannot be read is a `GQL510`.
+
+| Exit code | Meaning |
+|---|---|
+| `0` | Success; warnings such as `GQL506` do not change it. |
+| `1` | At least one error: a problem in the project, a failed schema fetch, or (for `check`) an outdated file. |
+| `64` | The command line itself is wrong: a missing or unknown command or option. The usage is printed. |
+
+When `schema` is a URL, the command posts the full introspection query to it
+(the response may be an introspection result or a GraphQL response around
+one) and uses the result as the schema; a network failure, a timeout or a
+response that is not an introspection result is a diagnostic, not a crash. A
+`${NAME}` in a value of `headers` is replaced by the environment variable
+`NAME`; an unset variable is a `GQL501`. The values are never printed, not in
+a diagnostic either. Put secrets there, not in `typed_graphql.yaml`:
+
+```text
+schema: https://example.com/graphql
+headers:
+  Authorization: Bearer ${GRAPHQL_TOKEN}
+```
+
+The `example/` folder of the package is a small project with its generated
+code checked in; `test/example_test.dart` generates it again and compares the
+files byte for byte.
+
 ## Document libraries
 
 Each document file gets a library at its own path plus `.dart`
@@ -839,6 +894,8 @@ and are never reused.
 | `GQL506` | warning | No document matches `documents`. |
 | `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`), a class of an operation and a fragment, two members of one class (such as the fields `user_name` and `userName`, or two fragments `UserCard` and `userCard`), or two files at one path. |
 | `GQL508` | error | A name the generator would declare hides a Dart type the generated code uses, such as `List`, or a `dart:core` type a scalar is mapped to. |
+| `GQL509` | error | `check` found a generated file that is missing or differs from what `generate` would write. |
+| `GQL510` | error | The command line cannot read the configuration, the schema file, a document or the schema URL (a network failure, a timeout, a non-success status or a body that is not an introspection result). |
 | `GQL511` | error | An operation or fragment would generate more than 10000 classes, for instance a selection on an interface that reaches many types, repeated under many aliases. |
 
 The problems of the schema and of the documents keep the codes of the core:
````

Create `packages/typed_graphql_codegen/example/README.md`:

````markdown
# typed_graphql_codegen example

A small project whose generated code is checked in.

- `typed_graphql.yaml`: the configuration.
- `schema.graphql`: the schema.
- `lib/user.graphql`: the operation `GetUser`.
- `lib/schema.graphql.dart` and `lib/user.graphql.dart`: the generated code.

To regenerate the code after a change, run in this folder:

```sh
dart run typed_graphql_codegen generate
```

`dart run typed_graphql_codegen check` exits with 1 when a generated file is
out of date. The test `test/example_test.dart` of the package runs the
generator on these inputs and expects the checked-in files byte for byte.

This folder has its own `pubspec.yaml` (`publish_to: none`) and is a member
of the repository's pub workspace: the generated code imports
`typed_graphql` and `typed_graphql_client`, which the code generator itself
does not depend on, so the repository's `dart analyze` needs them here.
````

Create `packages/typed_graphql_codegen/example/lib/schema.graphql.dart`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from schema.graphql.
// dart format off

import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// The enum `Role`.
sealed class Role implements client.DataEnum {
  /// The value named [raw]: a [RoleKnown], or a [RoleUnknown] for a name
  /// this code does not know.
  factory Role.parse(String raw) {
    for (final value in RoleKnown.values) {
      if (value.raw == raw) return value;
    }
    return RoleUnknown(raw);
  }

  /// Reads and writes the values of `Role`.
  static const client.DataCodec<Role> codec = client.EnumDataCodec(Role.parse);
}

/// The values of [Role] this code knows.
enum RoleKnown implements Role {
  /// `ADMIN`.
  admin('ADMIN'),

  /// `MEMBER`.
  member('MEMBER');

  const RoleKnown(this.raw);

  @override
  final String raw;
}

/// A value of [Role] this code does not know, such as one added to the
/// schema after the code was generated.
final class RoleUnknown implements Role {
  /// Creates the value named [raw].
  const RoleUnknown(this.raw);

  @override
  final String raw;

  @override
  bool operator ==(Object other) => other is RoleUnknown && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'RoleUnknown($raw)';
}
```

Create `packages/typed_graphql_codegen/example/lib/user.graphql`:

```graphql
query GetUser($id: ID!) {
  user(id: $id) {
    id
    name
    role
    email
  }
}
```

Create `packages/typed_graphql_codegen/example/lib/user.graphql.dart`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

import 'schema.graphql.dart';

/// The query `GetUser`.
final class GetUserQuery extends client.GraphQLQuery<GetUserData> {
  /// Creates the query with its [variables].
  const GetUserQuery(this.variables);

  /// The document of `GetUser` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'GetUser',
        type: graphql.OperationType.query,
        text: r'query GetUser($id:ID!){user(id:$id){id name role email __typename}}',
        sha256:
          'f9049a20cc2ca492d7c4f9da6a6925353b7a59faed143080ae8a93be9faae3d7',
      );

  /// The variables the query is sent with.
  final GetUserVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<GetUserData> decodeData(graphql.JsonObject data) =>
      GetUserData.decode(data, variables: variablesJson);
}

/// The variables of the query `GetUser`.
final class GetUserVariables implements client.DataObject {
  /// Creates the variables.
  const GetUserVariables({required this.id});

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The variable `$id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) => other is GetUserVariables && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GetUserVariables(id: $id)';
}

/// The data of the query `GetUser`.
final class GetUserData implements client.DataObject {
  /// Creates the data.
  const GetUserData({this.user});

  factory GetUserData._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserData(user: _userCodec.field(json, 'user', context));

  /// Reads and writes the data.
  static const client.DataCodec<GetUserData> codec =
      client.ObjectDataCodec(GetUserData._read);

  static const client.DataCodec<GetUserDataUser?> _userCodec =
      client.NullableDataCodec(GetUserDataUser.codec);

  /// The field `user`.
  final GetUserDataUser? user;

  /// Reads [json], the `data` of a response to the query sent with
  /// [variables].
  static graphql.DecodeResult<GetUserData> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'user': _userCodec.write(user)});

  @override
  bool operator ==(Object other) => other is GetUserData && other.user == user;

  @override
  int get hashCode => user.hashCode;

  @override
  String toString() => 'GetUserData(user: $user)';
}

/// The field `user` of [GetUserData].
final class GetUserDataUser implements client.DataObject {
  /// Creates the value.
  const GetUserDataUser({
    required this.id,
    required this.name,
    required this.role,
    this.email,
  });

  factory GetUserDataUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUser(
    id: _idCodec.field(json, 'id', context),
    name: _nameCodec.field(json, 'name', context),
    role: _roleCodec.field(json, 'role', context),
    email: _emailCodec.field(json, 'email', context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<GetUserDataUser> codec =
      client.ObjectDataCodec(GetUserDataUser._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<Role> _roleCodec = Role.codec;

  static const client.DataCodec<String?> _emailCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  /// The field `id`.
  final String id;

  /// The field `name`.
  final String name;

  /// The field `role`.
  final Role role;

  /// The field `email`.
  final String? email;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
    'role': _roleCodec.write(role),
    'email': _emailCodec.write(email),
  });

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUser &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.email == email;

  @override
  int get hashCode => Object.hashAll([id, name, role, email]);

  @override
  String toString() =>
      'GetUserDataUser(id: $id, name: $name, role: $role, email: $email)';
}
```

Create `packages/typed_graphql_codegen/example/pubspec.yaml`:

```yaml
name: typed_graphql_codegen_example
description: A project whose generated client code is checked in, for typed_graphql_codegen.
publish_to: none

environment:
  sdk: ^3.13.0

dependencies:
  typed_graphql: ^0.0.1
  typed_graphql_client: ^0.0.1

resolution: workspace
```

Create `packages/typed_graphql_codegen/example/schema.graphql`:

```graphql
type Query {
  user(id: ID!): User
}

type User {
  id: ID!
  name: String!
  role: Role!
  email: String
}

enum Role {
  ADMIN
  MEMBER
}
```

Create `packages/typed_graphql_codegen/example/typed_graphql.yaml`:

```yaml
schema: schema.graphql
documents: lib/**.graphql
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/example_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md docs/discovery.md docs/superpowers/HANDOFF.md llms.txt packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/README.md packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/example/README.md packages/typed_graphql_codegen/example/lib/schema.graphql.dart packages/typed_graphql_codegen/example/lib/user.graphql packages/typed_graphql_codegen/example/lib/user.graphql.dart packages/typed_graphql_codegen/example/pubspec.yaml packages/typed_graphql_codegen/example/schema.graphql packages/typed_graphql_codegen/example/typed_graphql.yaml packages/typed_graphql_codegen/test/example_test.dart pubspec.yaml
git commit -q -m "docs(typed_graphql_codegen): document the CLI and add the example" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Say that GQL504 covers only a sealed fragment at a subscription root

Carried from the M10c re-review (N3): the `GQL504` doc comment now says that an inline fragment alone is fine and that a subscription root needs `__typename` only when a spread, direct or inside an inline fragment, plans as a sealed base class.

Commit on the branch: `cb9cc65`.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: M10c Task 11 (`RootTypename`).
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -528,8 +528,10 @@ enum DiagnosticCode(
   anonymousOperation('GQL503'),
 
   /// `GQL504`: a construct the code generator does not support yet: `@defer`,
-  /// `@stream`, an introspection field (`__schema`, `__type`), or a spread or
-  /// inline fragment that makes the root of a subscription polymorphic.
+  /// `@stream`, an introspection field (`__schema`, `__type`), or a
+  /// subscription root that spreads (directly or inside an inline fragment) a
+  /// fragment which plans as a sealed base class; it would need `__typename`,
+  /// which a subscription cannot select. A plain inline fragment is fine.
   unsupportedInDocument('GQL504'),
 
   /// `GQL505`: the configuration maps a scalar the schema does not have as a
```

- [ ] **Step 2: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
git commit -q -m "docs(typed_graphql): say that GQL504 covers only a sealed fragment at a subscription root" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Keep a fragment's value when the class writes null

Carried from the M10c re-review (N1): `JsonMerger` let a later `JsonNull` replace a value an earlier fragment class wrote (a conditional field written as `null` erased a fragment's object); a null now never replaces a value, since one response name holds one value.

Commit on the branch: `5c1b333`.

**Files:**
- Modify: `packages/typed_graphql_client/CHANGELOG.md`, `packages/typed_graphql_client/lib/src/operation/json_merger.dart`
- Test: `packages/typed_graphql_client/test/operation/json_merger_test.dart`

**Interfaces:**
- Consumes: M10c Task 10 (`JsonMerger`).
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_client/test/operation/json_merger_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -60,13 +60,23 @@ void main() {
     );
   });
 
-  test('lets the later value win for other pairs', () {
+  test('keeps the fragment value when the later class writes null', () {
     expect(
       merger.merge([
         JsonObject({'a': JsonNumber(1)}),
         JsonObject({'a': const JsonNull()}),
       ]),
-      JsonObject({'a': const JsonNull()}),
+      JsonObject({'a': JsonNumber(1)}),
+    );
+  });
+
+  test('lets the later value win for other pairs', () {
+    expect(
+      merger.merge([
+        JsonObject({'a': JsonNumber(1)}),
+        JsonObject({'a': const JsonString('x')}),
+      ]),
+      JsonObject({'a': const JsonString('x')}),
     );
   });
 }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 600 dart test test/operation/json_merger_test.dart)
```

Expected: FAIL. The new and changed tests fail on the behaviour this task fixes (assertion failures; a test that uses a name the next step adds does not compile).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_client/lib/src/operation/json_merger.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,7 +7,9 @@ import 'package:typed_graphql/typed_graphql.dart';
 /// same response name with different sub-selections; the written object
 /// must hold the fields of both. Objects merge by key, recursively; arrays
 /// merge by index, as the reader reads the same list once per selection;
-/// for any other pair the later value wins.
+/// a null never replaces a value (a class that does not select a field
+/// writes null where its fragment wrote the object); for any other pair the
+/// later value wins.
 ///
 /// {@category operations}
 final class const JsonMerger() {
@@ -47,6 +49,7 @@ final class const JsonMerger() {
           base,
           extra,
         ),
+        (_, JsonNull()) => base,
         _ => extra,
       };
 
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 600 dart test test/operation/json_merger_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql_client/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -13,4 +13,4 @@
   `DataObject` and `DataFormatException`; the Generated Operations guide.
 - `JsonMerger` merges the JSON of a class and its fragments deeply (objects by
   key, arrays by index), so generated `toJson` keeps every field of
-  overlapping nested selections.
+  overlapping nested selections; a null never replaces a value.
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql_client/CHANGELOG.md packages/typed_graphql_client/lib/src/operation/json_merger.dart packages/typed_graphql_client/test/operation/json_merger_test.dart
git commit -q -m "fix(typed_graphql_client): keep a fragment's value when the class writes null" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Make the command line's I/O and HTTP fetch fail as diagnostics

The M10d review findings 1-11, 14 and 15 (`.superpowers/m10-reports/m10d-review.md`) and the carried secret items: the exit-code test skips itself under `--compiler exe` (1); output goes through `<path>.tmp` and a rename, and an unwritable or unreadable output is `GQL510`, never an exception (2, 11); an invalid documents glob is `GQL501`, a listing failure `GQL510`, and symbolic links are not followed (3, 9); the schema body is capped at 64 MiB while reading (4); a request that cannot be built, a body that is not UTF-8 and empty or non-ASCII header values each get their own diagnostic (5, 8); redirects are not followed and a 3xx names its target without query or user information (6); `SecretRedactor` hides header values, URL user information and query in everything printed and escapes control characters (7); switches over the sealed results (14); and the strengthened tests (15).

Commit on the branch: `0b5cb41`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/cli/secret_redactor.dart`
- Modify: `packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart`, `packages/typed_graphql_codegen/lib/src/cli/codegen_command_line.dart`, `packages/typed_graphql_codegen/lib/src/cli/diagnostic_printer.dart`, `packages/typed_graphql_codegen/lib/src/cli/header_expander.dart`, `packages/typed_graphql_codegen/lib/src/cli/output_writer.dart`, `packages/typed_graphql_codegen/lib/src/cli/project_read_result.dart`, `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`, `packages/typed_graphql_codegen/lib/src/cli/schema_fetcher.dart`
- Test: `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`, `packages/typed_graphql_codegen/test/cli/header_expander_test.dart`, `packages/typed_graphql_codegen/test/cli/output_writer_test.dart`, `packages/typed_graphql_codegen/test/cli/project_reading_test.dart`, `packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart`, `packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt`

**Interfaces:**
- Consumes: Tasks 2-4.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// cli/diagnostic_printer.dart
final class const DiagnosticPrinter([

// cli/header_expander.dart
  expand(

// cli/output_writer.dart
  List<Diagnostic> outdated(List<GeneratedFile> files)
enum _State

// cli/project_reader.dart
  Future<ProjectReadResult> _readProject(CodegenConfig config) async
  final List<String> secrets
  final List<String> secrets

// cli/schema_fetcher.dart
  final int maxBodyBytes
  Future<SchemaFetchResult> fetch(
  Future<Uint8List?> _readCapped(Stream<List<int>> body) async

// cli/secret_redactor.dart
final class const SecretRedactor(…)
  String redact(String text)
  String escapeAll(String text)
  String escapeTerminal(String text)
  String displayUrl(Uri url)
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,10 +3,14 @@ library;
 
 import 'dart:io';
 
+import 'package:path/path.dart' as p;
 import 'package:test/test.dart';
 
 import '../support/cli_project.dart';
 
+final bool _isDartTool =
+    p.basenameWithoutExtension(Platform.resolvedExecutable) == 'dart';
+
 void main() {
   late CliProject project;
   setUp(() => project = CliProject());
@@ -113,6 +117,7 @@ void main() {
     );
   });
 
+  // Under `--compiler exe` the resolved executable is the test binary.
   test('the executable passes the exit code to the process', () async {
     final result = Process.runSync(Platform.resolvedExecutable, [
       'run',
@@ -123,5 +128,5 @@ void main() {
     ]);
     expect(result.exitCode, 1);
     expect(result.stderr, contains('GQL509'));
-  });
+  }, skip: _isDartTool ? false : 'the tests do not run on the dart tool');
 }
```

In `packages/typed_graphql_codegen/test/cli/header_expander_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,7 +2,12 @@ import 'package:test/test.dart';
 import 'package:typed_graphql_codegen/src/cli/header_expander.dart';
 
 void main() {
-  const expander = HeaderExpander({'A': 'one', 'B': 'a\nb'});
+  const expander = HeaderExpander({
+    'A': 'one',
+    'B': 'a\nb',
+    'C': '',
+    'D': 'caf\u00e9',
+  });
 
   test('replaces every reference', () {
     final result = expander.expand({'X': r'${A}-${A}'});
@@ -20,7 +25,7 @@ void main() {
     expect(result.headers, isEmpty);
     expect(result.problems.map((d) => d.toString()), [
       "error GQL501: The header 'X' uses the environment variable 'NOPE', "
-          'which is not set.',
+          'which is not set or is empty.',
     ]);
   });
 
@@ -28,8 +33,31 @@ void main() {
     final result = expander.expand({'X': r'${B}'});
     expect(result.headers, isEmpty);
     expect(result.problems.map((d) => d.toString()), [
-      "error GQL501: The value of header 'X' must not have a control "
+      "error GQL501: The value of header 'X' must be ASCII without a control "
+          'character after its environment variables are expanded.',
+    ]);
+  });
+
+  test('an empty variable is GQL501 as if it were not set', () {
+    final result = expander.expand({'X': r'${C}'});
+    expect(result.headers, isEmpty);
+    expect(result.problems.map((d) => d.toString()), [
+      "error GQL501: The header 'X' uses the environment variable 'C', "
+          'which is not set or is empty.',
+    ]);
+  });
+
+  test('a value that is not ASCII is GQL501', () {
+    final result = expander.expand({'X': r'${D}'});
+    expect(result.headers, isEmpty);
+    expect(result.problems.map((d) => d.toString()), [
+      "error GQL501: The value of header 'X' must be ASCII without a control "
           'character after its environment variables are expanded.',
     ]);
   });
+
+  test('the secrets are the expanded values and the variable values', () {
+    final result = expander.expand({'X': r'Bearer ${A}'});
+    expect(result.secrets, ['Bearer one', 'one']);
+  });
 }
```

Create `packages/typed_graphql_codegen/test/cli/output_writer_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/cli/output_writer.dart';
import 'package:typed_graphql_codegen/src/generator/generated_file.dart';

void main() {
  late Directory directory;
  late OutputWriter writer;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('output_writer');
    writer = OutputWriter(directory.path);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  const file = GeneratedFile('lib/a.dart', 'a\n');
  const other = GeneratedFile('lib/b.dart', 'b\n');

  test('write creates the folder and leaves no temporary file', () {
    final result = writer.write([file]);
    expect(result.written, ['lib/a.dart']);
    expect(result.problems, isEmpty);
    expect(
      Directory('${directory.path}/lib').listSync().map((e) => e.path),
      ['${directory.path}/lib/a.dart'],
    );
  });

  test('a directory at an output path is GQL510 and the rest is written', () {
    Directory('${directory.path}/lib/a.dart').createSync(recursive: true);
    final result = writer.write([file, other]);
    expect(result.written, ['lib/b.dart']);
    expect(result.problems.map((d) => d.toString()), [
      startsWith("error GQL510: Cannot write 'lib/a.dart': "),
    ]);
    expect(File('${directory.path}/lib/a.dart.tmp').existsSync(), isFalse);
  });

  test('an output that is not UTF-8 is replaced by write', () {
    File('${directory.path}/lib/a.dart')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0xff, 0xfe]);
    final result = writer.write([file]);
    expect(result.written, ['lib/a.dart']);
    expect(File('${directory.path}/lib/a.dart').readAsStringSync(), 'a\n');
  });

  test('an output that is not UTF-8 is GQL510 for check', () {
    File('${directory.path}/lib/a.dart')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0xff, 0xfe]);
    expect(writer.outdated([file]).map((d) => d.toString()), [
      "error GQL510: Cannot read 'lib/a.dart': not a readable UTF-8 file.",
    ]);
  });

  test('a directory at an output path is GQL510 for check', () {
    Directory('${directory.path}/lib/a.dart').createSync(recursive: true);
    expect(writer.outdated([file]).map((d) => d.toString()), [
      "error GQL510: Cannot read 'lib/a.dart': not a readable UTF-8 file.",
    ]);
  });

  test('a missing file is GQL509 for check', () {
    expect(writer.outdated([file]).map((d) => d.toString()), [
      "error GQL509: The generated file 'lib/a.dart' is out of date; run "
          '`dart run typed_graphql_codegen generate`.',
    ]);
  });
}
```

Create `packages/typed_graphql_codegen/test/cli/project_reading_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_project.dart';

void main() {
  late CliProject project;
  setUp(() => project = CliProject());
  tearDown(() => project.delete());

  String settings() {
    final lines = project.file('typed_graphql.yaml').readAsLinesSync();
    return lines.join('\n');
  }

  void documents(String list) => project
      .file('typed_graphql.yaml')
      .writeAsStringSync('${settings()}\ndocuments: [$list]\n');

  test('an invalid documents pattern is GQL501', () async {
    documents('"lib/[.graphql"');
    expect(await project.run(['generate']), 1);
    expect(
      project.err.toString(),
      startsWith("error GQL501: The documents pattern 'lib/[.graphql' "),
    );
  });

  test('a symbolic link to a document is not followed', () async {
    final outside = File('${project.directory.path}/outside.txt')
      ..writeAsStringSync('query Outside { __typename }');
    Link('${project.directory.path}/lib/link.graphql').createSync(outside.path);
    expect(await project.run(['generate']), 0);
    expect(project.file('lib/link.graphql.dart').existsSync(), isFalse);
  });

  test('an unreadable document is GQL510', () async {
    project.file('lib/bad.graphql').writeAsBytesSync([0xff, 0xfe]);
    expect(await project.run(['generate']), 1);
    expect(
      project.err.toString(),
      startsWith("error GQL510: Cannot read 'lib/bad.graphql': "),
    );
  });

  test('check with only a warning exits 0 and prints it', () async {
    for (final path in ['user', 'user_mutations', 'user_subscriptions']) {
      project.file('lib/$path.graphql').deleteSync();
    }
    await project.run(['generate']);
    expect(await project.run(['check']), 0);
    expect(project.err.toString(), contains('warning GQL506'));
    expect(project.out.toString(), 'Up to date.\n');
  });

  test('check ignores a generated file whose document was removed', () async {
    await project.run(['generate']);
    project.file('lib/user_mutations.graphql').deleteSync();
    await project.run(['generate']);
    expect(await project.run(['check']), 0);
    expect(
      project.file('lib/user_mutations.graphql.dart').existsSync(),
      isTrue,
    );
  });
}
```

In `packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,6 +7,7 @@ import 'dart:io';
 
 import 'package:test/test.dart';
 import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_codegen/src/cli/schema_fetch_result.dart';
 import 'package:typed_graphql_codegen/src/cli/schema_fetcher.dart';
 
 import '../support/cli_project.dart';
@@ -79,10 +80,8 @@ void main() {
       'Bearer secret-token-value',
     );
     expect(requests.single.headers.contentType?.mimeType, 'application/json');
-    expect(
-      requests.single.body,
-      GraphQLRequest(query: IntrospectionQuery.full.text).toJson().toString(),
-    );
+    final body = jsonDecode(requests.single.body) as Map<String, Object?>;
+    expect(body['query'], IntrospectionQuery.full.text);
   });
 
   test('a 401 is GQL510 with the status', () async {
@@ -154,7 +153,7 @@ void main() {
     expect(
       project.err.toString(),
       "error GQL501: The header 'Authorization' uses the environment "
-      "variable 'TOKEN', which is not set.\n",
+      "variable 'TOKEN', which is not set or is empty.\n",
     );
     expect(requests, isEmpty);
   });
@@ -171,4 +170,141 @@ void main() {
       isNot(contains('secret-token-value')),
     );
   });
+
+  test('a redirect is GQL510 with the target and no query', () async {
+    respond = (response) {
+      response.statusCode = 307;
+      response.headers.set('location', '/moved?token=abc123');
+      response.close();
+    };
+    expect(await project.run(['generate'], environment: environment), 1);
+    expect(
+      project.err.toString(),
+      'error GQL510: Cannot fetch the schema from '
+      "'http://127.0.0.1:${server.port}/graphql': the server redirected "
+      '(HTTP 307) to http://127.0.0.1:${server.port}/moved; set `schema` to '
+      'that URL.\n',
+    );
+    expect(requests, hasLength(1));
+  });
+
+  test('a body past the cap is GQL510', () async {
+    respond = (response) {
+      response.write('x' * 5000);
+      response.close();
+    };
+    final code = await project.run(
+      ['generate'],
+      environment: environment,
+      fetcher: const SchemaFetcher(maxBodyBytes: 1000),
+    );
+    expect(code, 1);
+    expect(
+      project.err.toString(),
+      'error GQL510: Cannot fetch the schema from '
+      "'http://127.0.0.1:${server.port}/graphql': the response is larger "
+      'than 1000 bytes.\n',
+    );
+  });
+
+  test('a body that is not UTF-8 says so', () async {
+    respond = (response) {
+      response.add([0xff, 0xfe, 0xfd]);
+      response.close();
+    };
+    expect(await project.run(['generate'], environment: environment), 1);
+    expect(
+      project.err.toString(),
+      endsWith(': the response is not valid UTF-8.\n'),
+    );
+  });
+
+  test('a 200 that is not JSON is GQL502 at the URL', () async {
+    respond = (response) {
+      response.write('<html>');
+      response.close();
+    };
+    expect(await project.run(['generate'], environment: environment), 1);
+    expect(
+      project.err.toString(),
+      startsWith(
+        'http://127.0.0.1:${server.port}/graphql.json:1:1: error GQL502: ',
+      ),
+    );
+  });
+
+  test('a header the HTTP layer refuses is not a UTF-8 problem', () async {
+    final result = await const SchemaFetcher().fetch(
+      Uri.parse('http://127.0.0.1:${server.port}/graphql'),
+      {'bad name': 'x'},
+    );
+    expect(
+      (result as SchemaFetchFailed).diagnostic.message,
+      startsWith(
+        "Cannot fetch the schema from 'http://127.0.0.1:${server.port}"
+        "/graphql': the request cannot be built: ",
+      ),
+    );
+    expect(requests, isEmpty);
+  });
+
+  test('a body that echoes the header hides it and escapes controls', () async {
+    respond = (response) {
+      response.statusCode = 400;
+      response.write('\u001b[31mBearer secret-token-value\nsecret-token-value');
+      response.close();
+    };
+    expect(await project.run(['generate'], environment: environment), 1);
+    final text = project.err.toString();
+    expect(text, isNot(contains('secret-token-value')));
+    expect(text, isNot(contains('\u001b')));
+    expect(text, contains(r'HTTP 400 Bad Request: \u001b[31m***\u000a***.'));
+  });
+
+  test('an errors message that echoes the header is hidden', () async {
+    respond = (response) {
+      response.write(
+        jsonEncode({
+          'errors': [
+            {'message': 'bad token secret-token-value'},
+          ],
+        }),
+      );
+      response.close();
+    };
+    expect(await project.run(['generate'], environment: environment), 1);
+    expect(project.err.toString(), isNot(contains('secret-token-value')));
+    expect(project.err.toString(), contains('bad token ***'));
+  });
+
+  test('a token in the URL is never printed', () async {
+    project
+        .file('typed_graphql.yaml')
+        .writeAsStringSync(
+          'schema: http://user:pw1@127.0.0.1:${server.port}/graphql'
+          '?key=urltoken\n${keptSettings(project)}',
+        );
+    respond = (response) {
+      response.statusCode = 403;
+      response.write('denied urltoken pw1');
+      response.close();
+    };
+    expect(await project.run(['generate'], environment: environment), 1);
+    expect(
+      project.err.toString(),
+      'error GQL510: Cannot fetch the schema from '
+      "'http://127.0.0.1:${server.port}/graphql': HTTP 403 Forbidden: "
+      'denied *** ***.\n',
+    );
+  });
+
+  test('a successful fetch names the schema without the query', () async {
+    project
+        .file('typed_graphql.yaml')
+        .writeAsStringSync(
+          'schema: http://127.0.0.1:${server.port}/graphql?key=urltoken\n'
+          '${keptSettings(project)}',
+        );
+    expect(await project.run(['generate'], environment: environment), 0);
+  });
 }
```

In `packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -52,9 +52,14 @@ void main() {
 // A class and the fragments it spreads select `avatar` with different
 // sub-fields: toJson keeps the sub-fields of each.
 void _overlappingSelections() {
-  final JsonObject json = _json(
-    '{"avatar": {"url": "u", "size": 3}}',
-  );
+  _overlapRoundTrips('{"avatar": {"url": "u", "size": 3}}');
+  // A null object stays null: merging the class and its fragments must not
+  // lose it or invent a value.
+  _overlapRoundTrips('{"avatar": null}');
+}
+
+void _overlapRoundTrips(String text) {
+  final JsonObject json = _json(text);
   final DecodeResult<WithAvatars> result = WithAvatars.decode(json);
   if (result is! DecodeSuccess<WithAvatars>) {
     _fail('decode failed: $result');
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_test.dart test/cli/header_expander_test.dart test/cli/output_writer_test.dart test/cli/project_reading_test.dart test/cli/schema_fetcher_test.dart)
```

Expected: FAIL. The new and changed tests fail on the behaviour this task fixes (assertion failures; a test that uses a name the next step adds does not compile).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,6 +9,7 @@ import 'output_writer.dart';
 import 'project_read_result.dart';
 import 'project_reader.dart';
 import 'schema_fetcher.dart';
+import 'secret_redactor.dart';
 
 /// Runs the code generator's command line, with injected streams and working
 /// directory so tests run it in process.
@@ -71,30 +72,41 @@ final class CodegenCommand {
       environment: environment,
       fetcher: fetcher,
     ).read(p.basename(absolute));
-    if (project is! ProjectRead) {
-      return _report((project as ProjectReadFailed).diagnostics);
+    switch (project) {
+      case ProjectReadFailed(:final diagnostics, :final secrets):
+        return _report(diagnostics, secrets);
+      case ProjectRead():
+        return _generate(project, directory, isCheck: isCheck);
     }
+  }
+
+  int _generate(
+    ProjectRead project,
+    String directory, {
+    required bool isCheck,
+  }) {
     final result = ClientGenerator(
       project.config,
     ).generate(schema: project.schema, documents: project.documents);
-    if (result.hasErrors) return _report(result.diagnostics);
+    final secrets = project.secrets;
+    if (result.hasErrors) return _report(result.diagnostics, secrets);
     final writer = OutputWriter(directory);
     if (isCheck) {
       final outdated = writer.outdated(result.files);
-      final code = _report([...result.diagnostics, ...outdated]);
+      final code = _report([...result.diagnostics, ...outdated], secrets);
       if (outdated.isEmpty) out.writeln('Up to date.');
       return code;
     }
-    final written = writer.write(result.files);
-    final code = _report(result.diagnostics);
+    final (:written, :problems) = writer.write(result.files);
+    final code = _report([...result.diagnostics, ...problems], secrets);
     out.writeln(
       written.isEmpty ? 'Nothing to write.' : 'Wrote ${written.length} files.',
     );
     return code;
   }
 
-  int _report(List<Diagnostic> diagnostics) {
-    const printer = DiagnosticPrinter();
+  int _report(List<Diagnostic> diagnostics, [List<String> secrets = const []]) {
+    final printer = DiagnosticPrinter(SecretRedactor(secrets));
     for (final diagnostic in diagnostics) {
       err.writeln(printer.print(diagnostic));
     }
```

In `packages/typed_graphql_codegen/lib/src/cli/codegen_command_line.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,7 +21,7 @@ final class const CodegenCommandLine() {
       '  check     Fail when a generated file is missing or out of date.\n\n'
       '${_parser.usage}';
 
-  ArgParser get _parser => ArgParser()
+  static final ArgParser _parser = ArgParser()
     ..addOption(
       'config',
       abbr: 'c',
@@ -45,6 +45,9 @@ final class const CodegenCommandLine() {
         (rest.single != 'generate' && rest.single != 'check')) {
       return CommandLineUsageError('Unknown command "${rest.join(' ')}".');
     }
-    return CommandLineRun(rest.single == 'check', results.option('config')!);
+    return CommandLineRun(
+      rest.single == 'check',
+      results.option('config') ?? defaultConfigPath,
+    );
   }
 }
```

In `packages/typed_graphql_codegen/lib/src/cli/diagnostic_printer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,15 +1,21 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import 'secret_redactor.dart';
+
 /// Prints diagnostics for a terminal.
 ///
 /// {@category codegen}
-final class const DiagnosticPrinter() {
+final class const DiagnosticPrinter([
+  /// Hides secrets and escapes control characters in what is printed.
+  final SecretRedactor redactor = const SecretRedactor([]),
+]) {
   /// Creates the printer.
   this;
 
   /// [diagnostic] as `path:line:col: severity GQLnnn: message`, then the
   /// excerpt of its span and a note per related span; without a span,
-  /// `severity GQLnnn: message`.
+  /// `severity GQLnnn: message`. Secrets are hidden and control characters
+  /// escaped, so a server's text cannot drive the terminal.
   String print(Diagnostic diagnostic) {
     final lines = <String>[diagnostic.toString()];
     final span = diagnostic.span;
@@ -17,6 +23,6 @@ final class const DiagnosticPrinter() {
     for (final place in diagnostic.related) {
       lines.add('$place: note: related');
     }
-    return lines.join('\n');
+    return redactor.escapeTerminal(redactor.redact(lines.join('\n')));
   }
 }
```

In `packages/typed_graphql_codegen/lib/src/cli/header_expander.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,7 +5,9 @@ import 'package:typed_graphql/typed_graphql.dart';
 /// Only the exact form `${NAME}` with `NAME` of `[A-Za-z_][A-Za-z0-9_]*` is a
 /// reference; `$$`, a lone `$` and a `${` without `}` stay as written, so
 /// there is no escape syntax. A value is expanded once: the text an
-/// environment variable holds is not expanded again.
+/// environment variable holds is not expanded again. A variable that is
+/// empty counts as not set, and an expanded value must be ASCII (no control
+/// character but the tab), as an HTTP header value is sent as written.
 ///
 /// {@category codegen}
 final class const HeaderExpander(
@@ -16,14 +18,22 @@ final class const HeaderExpander(
   this;
 
   static final RegExp _reference = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
-  static final RegExp _control = RegExp(r'[\x00-\x08\x0A-\x1F\x7F]');
+  static final RegExp _forbidden = RegExp(r'[^\x09\x20-\x7E]');
 
   /// Expands every value of [headers]; the problems (`GQL501`) never hold a
   /// header value, and a header with a problem is left out of the result.
-  ({Map<String, String> headers, List<Diagnostic> problems}) expand(
+  /// [secrets] are the texts a printout must hide: each expanded value and
+  /// each variable's value.
+  ({
+    Map<String, String> headers,
+    List<String> secrets,
+    List<Diagnostic> problems,
+  })
+  expand(
     Map<String, String> headers,
   ) {
     final expanded = <String, String>{};
+    final secrets = <String>[];
     final problems = <Diagnostic>[];
     for (final MapEntry(:key, :value) in headers.entries) {
       final missing = _missing(value);
@@ -31,7 +41,7 @@ final class const HeaderExpander(
         problems.add(
           _problem(
             "The header '$key' uses the environment variable '$missing', "
-            'which is not set.',
+            'which is not set or is empty.',
           ),
         );
         continue;
@@ -40,24 +50,28 @@ final class const HeaderExpander(
         _reference,
         (match) => environment[match.group(1)]!,
       );
-      if (_control.hasMatch(text)) {
+      if (_forbidden.hasMatch(text)) {
         problems.add(
           _problem(
-            "The value of header '$key' must not have a control character "
-            'after its environment variables are expanded.',
+            "The value of header '$key' must be ASCII without a control "
+            'character after its environment variables are expanded.',
           ),
         );
         continue;
       }
       expanded[key] = text;
+      secrets.add(text);
+      for (final match in _reference.allMatches(value)) {
+        secrets.add(environment[match.group(1)]!);
+      }
     }
-    return (headers: expanded, problems: problems);
+    return (headers: expanded, secrets: secrets, problems: problems);
   }
 
   String? _missing(String value) {
     for (final match in _reference.allMatches(value)) {
       final name = match.group(1)!;
-      if (!environment.containsKey(name)) return name;
+      if (environment[name]?.isEmpty ?? true) return name;
     }
     return null;
   }
```

In `packages/typed_graphql_codegen/lib/src/cli/output_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,6 +8,9 @@ import '../generator/generated_file.dart';
 /// Writes generated files under the project directory, or reports which of
 /// them are out of date.
 ///
+/// It looks only at the files the generator emits: a generated file whose
+/// document was removed is neither deleted nor reported.
+///
 /// {@category codegen}
 final class const OutputWriter(
   /// The directory of the configuration file; generated paths are relative
@@ -17,35 +20,92 @@ final class const OutputWriter(
   /// Creates a writer for the project in [directory].
   this;
 
-  /// Writes every file of [files] whose content differs; never deletes.
-  /// Returns the paths written.
-  List<String> write(List<GeneratedFile> files) {
+  /// Writes every file of [files] whose content differs, through a temporary
+  /// file in the same folder and a rename so that an interrupted run never
+  /// leaves a truncated file; never deletes. Returns the paths written and a
+  /// `GQL510` per file it could not write (the others are still written).
+  ({List<String> written, List<Diagnostic> problems}) write(
+    List<GeneratedFile> files,
+  ) {
     final written = <String>[];
+    final problems = <Diagnostic>[];
+    for (final generated in files) {
+      if (_state(generated) == _State.current) continue;
+      try {
+        _replace(generated);
+        written.add(generated.path);
+      } on FileSystemException catch (error) {
+        problems.add(
+          _problem(
+            'write',
+            generated.path,
+            error.osError?.message ?? error.message,
+          ),
+        );
+      }
+    }
+    return (written: written, problems: problems);
+  }
+
+  /// A `GQL509` per file of [files] that is missing or differs and a `GQL510`
+  /// per file that exists but cannot be read; writes nothing.
+  List<Diagnostic> outdated(List<GeneratedFile> files) {
+    final found = <Diagnostic>[];
     for (final generated in files) {
-      if (_isCurrent(generated)) continue;
-      final file = File(p.join(directory, generated.path));
-      file.parent.createSync(recursive: true);
-      file.writeAsStringSync(generated.text);
-      written.add(generated.path);
+      switch (_state(generated)) {
+        case _State.current:
+          break;
+        case _State.outdated:
+          found.add(
+            Diagnostic(
+              .outputOutdated,
+              .error,
+              "The generated file '${generated.path}' is out of date; run "
+              '`dart run typed_graphql_codegen generate`.',
+            ),
+          );
+        case _State.unreadable:
+          found.add(
+            _problem('read', generated.path, 'not a readable UTF-8 file'),
+          );
+      }
+    }
+    return found;
+  }
+
+  void _replace(GeneratedFile generated) {
+    final file = File(p.join(directory, generated.path));
+    file.parent.createSync(recursive: true);
+    final temporary = File('${file.path}.tmp');
+    try {
+      temporary.writeAsStringSync(generated.text);
+      temporary.renameSync(file.path);
+    } on FileSystemException {
+      if (temporary.existsSync()) temporary.deleteSync();
+      rethrow;
     }
-    return written;
   }
 
-  /// A `GQL509` per file of [files] that is missing or differs; writes
-  /// nothing.
-  List<Diagnostic> outdated(List<GeneratedFile> files) => [
-    for (final generated in files)
-      if (!_isCurrent(generated))
-        Diagnostic(
-          .outputOutdated,
-          .error,
-          "The generated file '${generated.path}' is out of date; run "
-          '`dart run typed_graphql_codegen generate`.',
-        ),
-  ];
-
-  bool _isCurrent(GeneratedFile generated) {
+  _State _state(GeneratedFile generated) {
     final file = File(p.join(directory, generated.path));
-    return file.existsSync() && file.readAsStringSync() == generated.text;
+    try {
+      if (FileSystemEntity.isDirectorySync(file.path)) return _State.unreadable;
+      if (!file.existsSync()) return _State.outdated;
+      return file.readAsStringSync() == generated.text
+          ? _State.current
+          : _State.outdated;
+    } on FileSystemException {
+      return _State.unreadable;
+    } on FormatException {
+      return _State.unreadable;
+    }
   }
+
+  Diagnostic _problem(String verb, String path, String reason) => Diagnostic(
+    .inputUnreadable,
+    .error,
+    "Cannot $verb '$path': $reason.",
+  );
 }
+
+enum _State { current, outdated, unreadable }
```

In `packages/typed_graphql_codegen/lib/src/cli/project_read_result.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,6 +20,10 @@ final class ProjectRead(
   /// The schema file.
   final ProjectFile schema,
   List<ProjectFile> documents,
+
+  /// The texts to hide when anything of this project is printed, such as the
+  /// expanded header values.
+  final List<String> secrets,
 ) extends ProjectReadResult {
   /// Creates the result.
   this;
@@ -32,8 +36,11 @@ final class ProjectRead(
 ///
 /// {@category codegen}
 final class ProjectReadFailed(
-  List<Diagnostic> diagnostics,
-) extends ProjectReadResult {
+  List<Diagnostic> diagnostics, [
+
+  /// The texts to hide when the problems are printed.
+  final List<String> secrets = const [],
+]) extends ProjectReadResult {
   /// Creates the result.
   this;
 
```

In `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -38,66 +38,115 @@ final class ProjectReader {
 
   /// Reads the project whose configuration is the file [configName].
   Future<ProjectReadResult> read(String configName) async {
-    final configText = _readText(configName);
-    if (configText is! _FileText) {
-      return ProjectReadFailed([(configText as _FileFailed).problem]);
+    switch (_readText(configName)) {
+      case _FileFailed(:final problem):
+        return ProjectReadFailed([problem]);
+      case _FileText(:final text):
+        switch (CodegenConfig.parse(text, path: configName)) {
+          case ConfigFailure(:final diagnostics):
+            return ProjectReadFailed(diagnostics);
+          case ConfigSuccess(:final config):
+            return _readProject(config);
+        }
     }
-    final parsed = CodegenConfig.parse(configText.text, path: configName);
-    if (parsed is ConfigFailure) return ProjectReadFailed(parsed.diagnostics);
-    final config = (parsed as ConfigSuccess).config;
-    final schema = await _readSchema(config);
-    return switch (schema) {
-      _Text(:final file) => _readSources(config, file),
-      _Failed(:final problems) => ProjectReadFailed(problems),
+  }
+
+  Future<ProjectReadResult> _readProject(CodegenConfig config) async {
+    return switch (await _readSchema(config)) {
+      _Text(:final file, :final secrets) => _readSources(config, file, secrets),
+      _Failed(:final problems, :final secrets) => ProjectReadFailed(
+        problems,
+        secrets,
+      ),
     };
   }
 
   Future<_SchemaOutcome> _readSchema(CodegenConfig config) async {
     switch (config.schema) {
       case SchemaFile(:final path):
-        final text = _readText(path);
-        return switch (text) {
-          _FileText() => _Text(ProjectFile(path, text.text)),
-          _FileFailed() => _Failed([text.problem]),
+        return switch (_readText(path)) {
+          _FileText(:final text) => _Text(ProjectFile(path, text), const []),
+          _FileFailed(:final problem) => _Failed([problem], const []),
         };
       case SchemaUrl(:final url):
         final expansion = HeaderExpander(environment).expand(config.headers);
-        if (expansion.problems.isNotEmpty) return _Failed(expansion.problems);
-        return switch (await fetcher.fetch(url, expansion.headers)) {
-          SchemaFetched(:final file) => _Text(file),
-          SchemaFetchFailed(:final diagnostic) => _Failed([diagnostic]),
+        if (expansion.problems.isNotEmpty) {
+          return _Failed(expansion.problems, expansion.secrets);
+        }
+        final fetched = await fetcher.fetch(
+          url,
+          expansion.headers,
+          secrets: expansion.secrets,
+        );
+        return switch (fetched) {
+          SchemaFetched(:final file) => _Text(file, expansion.secrets),
+          SchemaFetchFailed(:final diagnostic) => _Failed(
+            [diagnostic],
+            expansion.secrets,
+          ),
         };
     }
   }
 
-  ProjectReadResult _readSources(CodegenConfig config, ProjectFile schema) {
-    final problems = <Diagnostic>[];
+  ProjectReadResult _readSources(
+    CodegenConfig config,
+    ProjectFile schema,
+    List<String> secrets,
+  ) {
+    final listing = _documentPaths(config, schema.path);
+    final problems = [...listing.problems];
     final documents = <ProjectFile>[];
-    for (final path in _documentPaths(config, schema.path)) {
-      final text = _readText(path);
-      switch (text) {
-        case _FileText():
-          documents.add(ProjectFile(path, text.text));
-        case _FileFailed():
-          problems.add(text.problem);
+    for (final path in listing.paths) {
+      switch (_readText(path)) {
+        case _FileText(:final text):
+          documents.add(ProjectFile(path, text));
+        case _FileFailed(:final problem):
+          problems.add(problem);
       }
     }
-    if (problems.isNotEmpty) return ProjectReadFailed(problems);
-    return ProjectRead(config, schema, documents);
+    if (problems.isNotEmpty) return ProjectReadFailed(problems, secrets);
+    return ProjectRead(config, schema, documents, secrets);
   }
 
-  List<String> _documentPaths(CodegenConfig config, String schemaPath) {
+  // Symbolic links are not followed: a link to a file outside the project
+  // would get around the rule that paths stay inside it.
+  ({List<String> paths, List<Diagnostic> problems}) _documentPaths(
+    CodegenConfig config,
+    String schemaPath,
+  ) {
     final paths = <String>{};
+    final problems = <Diagnostic>[];
     for (final pattern in config.documents) {
-      for (final entity in Glob(pattern).listSync(root: directory)) {
-        if (entity is! File || !entity.path.endsWith('.graphql')) continue;
-        final relative = p.posix.joinAll(
-          p.split(p.relative(entity.path, from: directory)),
+      try {
+        final entities = Glob(pattern).listSync(
+          root: directory,
+          followLinks: false,
+        );
+        for (final entity in entities) {
+          if (entity is! File || !entity.path.endsWith('.graphql')) continue;
+          final relative = p.posix.joinAll(
+            p.split(p.relative(entity.path, from: directory)),
+          );
+          if (relative != schemaPath) paths.add(relative);
+        }
+      } on FormatException catch (error) {
+        problems.add(
+          Diagnostic(
+            .invalidConfig,
+            .error,
+            "The documents pattern '$pattern' is not valid: ${error.message}.",
+          ),
+        );
+      } on FileSystemException catch (error) {
+        problems.add(
+          _unreadable(
+            pattern,
+            error.osError?.message ?? error.message,
+          ),
         );
-        if (relative != schemaPath) paths.add(relative);
       }
     }
-    return paths.toList()..sort();
+    return (paths: paths.toList()..sort(), problems: problems);
   }
 
   _FileOutcome _readText(String path) {
@@ -138,11 +187,13 @@ sealed class _SchemaOutcome {
 }
 
 final class _Text extends _SchemaOutcome {
-  const _Text(this.file);
+  const _Text(this.file, this.secrets);
   final ProjectFile file;
+  final List<String> secrets;
 }
 
 final class _Failed extends _SchemaOutcome {
-  const _Failed(this.problems);
+  const _Failed(this.problems, this.secrets);
   final List<Diagnostic> problems;
+  final List<String> secrets;
 }
```

In `packages/typed_graphql_codegen/lib/src/cli/schema_fetcher.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,45 +1,72 @@
 import 'dart:async';
 import 'dart:convert';
 import 'dart:io';
+import 'dart:typed_data';
 
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../project/project_file.dart';
 import 'schema_fetch_result.dart';
+import 'secret_redactor.dart';
 
 /// Fetches a schema by posting the full introspection query to a URL.
 ///
+/// It does not follow redirects: a 3xx is reported with the URL to use. What
+/// the diagnostics print of the URL and of the response has the header
+/// values hidden and no user information or query.
+///
 /// {@category codegen}
 final class SchemaFetcher {
-  /// Creates a fetcher; [timeout] bounds the whole exchange, and
-  /// [clientFactory] makes the HTTP client (tests inject their own).
+  /// Creates a fetcher; [timeout] bounds the whole exchange, [maxBodyBytes]
+  /// the response body, and [clientFactory] makes the HTTP client (tests
+  /// inject their own).
   const SchemaFetcher({
     this.timeout = const Duration(seconds: 30),
+    this.maxBodyBytes = defaultMaxBodyBytes,
     this.clientFactory = HttpClient.new,
   });
 
+  /// The default cap of the response body: 64 MiB.
+  static const int defaultMaxBodyBytes = 64 * 1024 * 1024;
+
   /// How long the request, the response and the body may take together.
   final Duration timeout;
 
+  /// The most bytes of response body the fetcher reads; it stops reading at
+  /// the first byte past it.
+  final int maxBodyBytes;
+
   /// Makes the client of one fetch; the fetcher closes it.
   final HttpClient Function() clientFactory;
 
   static const int _bodyExcerptLength = 200;
 
   /// Posts the introspection query to [url] with [headers]; never throws.
-  Future<SchemaFetchResult> fetch(Uri url, Map<String, String> headers) async {
+  /// [secrets] are further texts to hide from what is reported, such as the
+  /// values of the environment variables the headers used.
+  Future<SchemaFetchResult> fetch(
+    Uri url,
+    Map<String, String> headers, {
+    List<String> secrets = const [],
+  }) async {
+    final redactor = SecretRedactor([
+      ...headers.values,
+      ...secrets,
+      ...url.userInfo.split(':'),
+      url.userInfo,
+      ...url.queryParameters.values,
+      url.query,
+    ]);
     final client = clientFactory();
     try {
-      return await _exchange(client, url, headers).timeout(timeout);
+      return await _exchange(client, url, headers, redactor).timeout(timeout);
     } on TimeoutException {
       final limit = timeout.inMilliseconds % 1000 == 0
           ? '${timeout.inSeconds}s'
           : '${timeout.inMilliseconds}ms';
-      return _failed(url, 'the request timed out after $limit');
+      return _failed(url, 'the request timed out after $limit', redactor);
     } on IOException catch (error) {
-      return _failed(url, _describe(error));
-    } on FormatException {
-      return _failed(url, 'the response is not valid UTF-8');
+      return _failed(url, _describe(error), redactor);
     } finally {
       client.close(force: true);
     }
@@ -49,28 +76,92 @@ final class SchemaFetcher {
     HttpClient client,
     Uri url,
     Map<String, String> headers,
+    SecretRedactor redactor,
   ) async {
-    final request = await client.postUrl(url);
-    request.headers
-      ..contentType = ContentType.json
-      ..set(
-        HttpHeaders.acceptHeader,
-        'application/graphql-response+json, application/json',
+    final HttpClientRequest request;
+    try {
+      request = await client.postUrl(url);
+      request
+        ..followRedirects = false
+        ..headers.contentType = ContentType.json
+        ..headers.set(
+          HttpHeaders.acceptHeader,
+          'application/graphql-response+json, application/json',
+        );
+      for (final MapEntry(:key, :value) in headers.entries) {
+        request.headers.set(key, value);
+      }
+    } on FormatException catch (error) {
+      return _failed(
+        url,
+        'the request cannot be built: ${error.message}',
+        redactor,
       );
-    for (final MapEntry(:key, :value) in headers.entries) {
-      request.headers.set(key, value);
     }
     request.add(utf8.encode(_body));
     final response = await request.close();
-    final text = await utf8.decodeStream(response);
-    if (response.statusCode < 200 || response.statusCode > 299) {
-      final excerpt = text.length > _bodyExcerptLength
-          ? text.substring(0, _bodyExcerptLength)
-          : text;
-      final status = '${response.statusCode} ${response.reasonPhrase}';
-      return _failed(url, 'HTTP $status: $excerpt');
+    return _read(url, response, redactor);
+  }
+
+  Future<SchemaFetchResult> _read(
+    Uri url,
+    HttpClientResponse response,
+    SecretRedactor redactor,
+  ) async {
+    final status = response.statusCode;
+    final location = response.headers.value(HttpHeaders.locationHeader);
+    if (status >= 300 && status < 400 && location != null) {
+      final target = redactor.displayUrl(url.resolve(location));
+      return _failed(
+        url,
+        'the server redirected (HTTP $status) to $target; set `schema` to '
+        'that URL',
+        redactor,
+      );
+    }
+    final bytes = await _readCapped(response);
+    if (bytes == null) {
+      return _failed(
+        url,
+        'the response is larger than $maxBodyBytes bytes',
+        redactor,
+      );
+    }
+    final String text;
+    try {
+      text = utf8.decode(bytes);
+    } on FormatException {
+      return _failed(url, 'the response is not valid UTF-8', redactor);
+    }
+    if (status >= 200 && status <= 299) {
+      return SchemaFetched(
+        ProjectFile('${redactor.displayUrl(url)}.json', text),
+      );
     }
-    return SchemaFetched(ProjectFile('$url.json', text));
+    return _failed(url, _statusReason(response, text, redactor), redactor);
+  }
+
+  String _statusReason(
+    HttpClientResponse response,
+    String text,
+    SecretRedactor redactor,
+  ) {
+    final excerpt = redactor.escapeAll(redactor.redact(text));
+    final shown = excerpt.length > _bodyExcerptLength
+        ? excerpt.substring(0, _bodyExcerptLength)
+        : excerpt;
+    final head = 'HTTP ${response.statusCode} ${response.reasonPhrase}';
+    return shown.isEmpty ? head : '$head: $shown';
+  }
+
+  // Null when the body is past the cap; reading stops there.
+  Future<Uint8List?> _readCapped(Stream<List<int>> body) async {
+    final bytes = BytesBuilder(copy: false);
+    await for (final chunk in body) {
+      bytes.add(chunk);
+      if (bytes.length > maxBodyBytes) return null;
+    }
+    return bytes.takeBytes();
   }
 
   String get _body => GraphQLRequest(
@@ -83,11 +174,15 @@ final class SchemaFetcher {
     _ => error.toString(),
   };
 
-  SchemaFetchFailed _failed(Uri url, String reason) => SchemaFetchFailed(
-    Diagnostic(
-      .inputUnreadable,
-      .error,
-      "Cannot fetch the schema from '$url': $reason.",
-    ),
-  );
+  SchemaFetchFailed _failed(Uri url, String reason, SecretRedactor redactor) =>
+      SchemaFetchFailed(
+        Diagnostic(
+          .inputUnreadable,
+          .error,
+          redactor.redact(
+            "Cannot fetch the schema from '${redactor.displayUrl(url)}': "
+            '$reason.',
+          ),
+        ),
+      );
 }
```

Create `packages/typed_graphql_codegen/lib/src/cli/secret_redactor.dart`:

```dart
/// Keeps secrets and terminal control characters out of what the command line
/// prints.
///
/// {@category codegen}
final class const SecretRedactor(
  /// The texts to hide, such as expanded header values; an empty one is
  /// ignored.
  final List<String> secrets,
) {
  /// Creates a redactor for [secrets].
  this;

  static final RegExp _control = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _keptControl = RegExp(r'[\x00-\x08\x0B-\x1F\x7F]');

  /// [text] with every secret replaced by `***`, longest first so that a
  /// secret inside another is hidden whole.
  String redact(String text) {
    final ordered = [
      for (final secret in secrets)
        if (secret.isNotEmpty) secret,
    ]..sort((a, b) => b.length.compareTo(a.length));
    var result = text;
    for (final secret in ordered) {
      result = result.replaceAll(secret, '***');
    }
    return result;
  }

  /// [text] on one line: every control character, line breaks included,
  /// becomes a `\uXXXX` escape.
  String escapeAll(String text) => _escape(text, _control);

  /// [text] with the control characters that could drive a terminal (all but
  /// the tab and the line feed) escaped as `\uXXXX`.
  String escapeTerminal(String text) => _escape(text, _keptControl);

  /// [url] as it may be printed: without user information, query and
  /// fragment, which may hold a token.
  String displayUrl(Uri url) => Uri(
    scheme: url.scheme,
    host: url.host,
    port: url.hasPort ? url.port : null,
    path: url.path,
  ).toString();

  String _escape(String text, RegExp pattern) => text.replaceAllMapped(
    pattern,
    (match) =>
        '\\u${match.group(0)!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
  );
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_test.dart test/cli/header_expander_test.dart test/cli/output_writer_test.dart test/cli/project_reading_test.dart test/cli/schema_fetcher_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart packages/typed_graphql_codegen/lib/src/cli/codegen_command_line.dart packages/typed_graphql_codegen/lib/src/cli/diagnostic_printer.dart packages/typed_graphql_codegen/lib/src/cli/header_expander.dart packages/typed_graphql_codegen/lib/src/cli/output_writer.dart packages/typed_graphql_codegen/lib/src/cli/project_read_result.dart packages/typed_graphql_codegen/lib/src/cli/project_reader.dart packages/typed_graphql_codegen/lib/src/cli/schema_fetcher.dart packages/typed_graphql_codegen/lib/src/cli/secret_redactor.dart packages/typed_graphql_codegen/test/cli/codegen_command_test.dart packages/typed_graphql_codegen/test/cli/header_expander_test.dart packages/typed_graphql_codegen/test/cli/output_writer_test.dart packages/typed_graphql_codegen/test/cli/project_reading_test.dart packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt
git commit -q -m "fix(typed_graphql_codegen): make the command line's I/O and HTTP fetch fail as diagnostics" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Document the CLI's limits and merge the changelog entries

The M10d review documentation findings 10, 12, 13 and 16: the guide says that `check` and `generate` ignore generated files whose document was removed, that symbolic links are not followed, that redirects are not followed and that plain `http://` is accepted; the `GQL510` row matches the fetcher; the CHANGELOG duplicates are merged; the README says to add the package as a dev dependency and the example README explains the workspace resolution.

Commit on the branch: `ce7738f`.

**Files:**
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/README.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`, `packages/typed_graphql_codegen/example/README.md`

**Interfaces:**
- Consumes: Tasks 1-8.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Update the documents**

In `packages/typed_graphql_codegen/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -71,22 +71,19 @@
   needs `__typename` at the root of an operation (and is a `GQL504` in a
   subscription); name problems are limited like every other run; `GQL507`
   names the two classes of a variant for a type called `Unknown`.
-- `dart run typed_graphql_codegen generate` writes the generated files and
-  `check` fails when one is missing or out of date (`GQL509`); a file the
-  command cannot read is `GQL510`. `--config` names the configuration file.
-  `generate` never deletes a file. `CodegenCommand` (in `src/cli/`, not exported: it imports `dart:io`) runs
-  both in process.
+- `dart run typed_graphql_codegen generate` writes the changed files (through
+  a temporary file and a rename) and never deletes; `check` fails with
+  `GQL509` when a file is missing or out of date and writes nothing.
+  `--config` names the configuration file; exit codes are 0, 1 and 64. A file
+  the command cannot read or write is `GQL510`. `CodegenCommand` (in
+  `src/cli/`, not exported: it imports `dart:io`) runs it in process.
 - A `schema:` URL is fetched with a POST of the full introspection query
-  (`SchemaFetcher`, 30 s timeout); a failure is `GQL510` with the status, and
-  a response with `errors` and no `data` is `GQL502`. Header values may use
-  `${NAME}` (`HeaderExpander`): a variable that is not set is `GQL501`, a line
-  break from a variable is refused, and no header value is ever printed.
-- The command line `dart run typed_graphql_codegen generate|check [--config]`:
-  `generate` writes the changed files and never deletes; `check` reports
-  `GQL509` for a missing or outdated file; exit codes 0, 1 and 64; unreadable
-  inputs are `GQL510`.
-- A `schema` URL is fetched with the full introspection query; `${NAME}` in
-  `headers` is read from the environment and values are never printed.
+  (`SchemaFetcher`: 30 s timeout, 64 MiB body cap, redirects not followed);
+  a failure is `GQL510` and a response with `errors` and no `data` is
+  `GQL502`. Header values may use `${NAME}` (`HeaderExpander`): a variable
+  that is not set or is empty is `GQL501`, and so is a value that is not
+  ASCII. Header values are hidden (`***`) in everything printed, and the
+  URL is printed without user information and query.
 - The README's quick start, the guide's "Command line" section and the
   `example/` project with its generated code checked in
   (`test/example_test.dart`).
```

In `packages/typed_graphql_codegen/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -19,7 +19,8 @@ schema: schema.graphql
 documents: lib/**.graphql
 ```
 
-Then run it; `check` exits with 1 when a generated file is out of date:
+Add the package to your project (`dart pub add --dev typed_graphql_codegen`),
+then run it; `check` exits with 1 when a generated file is out of date:
 
 ```sh
 dart run typed_graphql_codegen generate
````

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -182,7 +182,12 @@ relative to the file's folder. `--help` prints the usage.
 checks and, when there is no error, writes each generated file whose text
 differs from what is on disk (creating folders as needed). It prints
 `Wrote N files.` or `Nothing to write.` and never deletes a file: a library
-whose document you removed stays until you delete it. `check` writes nothing;
+whose document you removed stays until you delete it, and neither `generate`
+nor `check` looks at it, so `check` can be clean while a stale library is
+still compiled. A file is written through a temporary file and a rename; a
+file that cannot be written is a `GQL510` and the others are still written.
+The `documents` globs do not follow symbolic links, and an invalid glob is a
+`GQL501`. `check` writes nothing;
 it reports a `GQL509` for each generated file that is missing or differs, and
 prints `Up to date.` when none does, so a CI job can run it to catch generated
 code that was not regenerated. Nothing is written when a document has an
@@ -201,11 +206,18 @@ configuration, the schema, a document) that cannot be read is a `GQL510`.
 
 When `schema` is a URL, the command posts the full introspection query to it
 (the response may be an introspection result or a GraphQL response around
-one) and uses the result as the schema; a network failure, a timeout or a
-response that is not an introspection result is a diagnostic, not a crash. A
-`${NAME}` in a value of `headers` is replaced by the environment variable
-`NAME`; an unset variable is a `GQL501`. The values are never printed, not in
-a diagnostic either. Put secrets there, not in `typed_graphql.yaml`:
+one) and uses the result as the schema. A network failure, a timeout, a
+redirect (not followed: the diagnostic names the URL to put in `schema`), a
+body over 64 MiB, a non-success status or an unreadable body is a `GQL510`;
+a body that is not an introspection result is a `GQL502`. A `${NAME}` in a
+value of `headers` is replaced by the environment variable `NAME`; a
+variable that is not set or is empty is a `GQL501`, and so is a value that
+is not ASCII. The tool never prints a header value, and it hides them (and
+the user information and query of the URL) in what it prints of the server's
+answer, but a server can echo a value in a form it changed, so keep secrets
+out of URLs. Everything printed is free of terminal control characters. The
+command sends the headers also over plain `http`; use `https` for secrets.
+Put secrets in `headers`, not in `typed_graphql.yaml`:
 
 ```text
 schema: https://example.com/graphql
@@ -895,7 +907,7 @@ and are never reused.
 | `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`), a class of an operation and a fragment, two members of one class (such as the fields `user_name` and `userName`, or two fragments `UserCard` and `userCard`), or two files at one path. |
 | `GQL508` | error | A name the generator would declare hides a Dart type the generated code uses, such as `List`, or a `dart:core` type a scalar is mapped to. |
 | `GQL509` | error | `check` found a generated file that is missing or differs from what `generate` would write. |
-| `GQL510` | error | The command line cannot read the configuration, the schema file, a document or the schema URL (a network failure, a timeout, a non-success status or a body that is not an introspection result). |
+| `GQL510` | error | The command line cannot read the configuration, the schema file, a document or the schema URL (a network failure, a timeout, a redirect, a body over 64 MiB, a non-success status or an unreadable body). |
 | `GQL511` | error | An operation or fragment would generate more than 10000 classes, for instance a selection on an interface that reaches many types, repeated under many aliases. |
 
 The problems of the schema and of the documents keep the codes of the core:
````

In `packages/typed_graphql_codegen/example/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,3 +21,8 @@ This folder has its own `pubspec.yaml` (`publish_to: none`) and is a member
 of the repository's pub workspace: the generated code imports
 `typed_graphql` and `typed_graphql_client`, which the code generator itself
 does not depend on, so the repository's `dart analyze` needs them here.
+
+`resolution: workspace` in its `pubspec.yaml` means the example resolves
+only inside this repository. In your own project, add
+`typed_graphql_codegen` as a dev dependency (`dart pub add --dev
+typed_graphql_codegen`) and run the same commands there.
```

- [ ] **Step 2: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/README.md packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/example/README.md
git commit -q -m "docs(typed_graphql_codegen): document the CLI's limits and merge the changelog entries" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: Suffix field names that shadow a type or annotation

Final review, Important 1: a field, variable, input field or enum value named `int`, `bool`, `double`, `num` or `override` shadowed the type or the annotation the generated members use, so the class did not compile. `DartNames` reserves them (`objectMembers`, `enumMembers`), so they get the `$` suffix; the operations golden gains a `Stats` type with such fields, a leading-underscore field, an enum whose values need `$`, a nested list and non-Boolean variable defaults.

Commit on the branch: `ff12ca7`.

**Files:**
- Modify: `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`
- Test: `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`, `packages/typed_graphql_codegen/test/cli/project_reading_test.dart`, `packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart`, `packages/typed_graphql_codegen/test/emit/dart_names_test.dart`, `packages/typed_graphql_codegen/test/goldens/operations/input/lib/stats.graphql`, `packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql`, `packages/typed_graphql_codegen/test/goldens/operations/output/build/persisted_operations.json.golden`, `packages/typed_graphql_codegen/test/goldens/operations/output/lib/schema.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/operations/output/lib/stats.graphql.dart.golden`

**Interfaces:**
- Consumes: Task 8 and M10b/M10c `DartNames`.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,7 +20,7 @@ void main() {
 
   test('generate writes the files of the goldens', () async {
     expect(await project.run(['generate']), 0);
-    expect(project.out.toString(), 'Wrote 5 files.\n');
+    expect(project.out.toString(), 'Wrote 6 files.\n');
     for (final golden in Directory(
       'test/goldens/operations/output',
     ).listSync(recursive: true).whereType<File>()) {
@@ -93,7 +93,12 @@ void main() {
   });
 
   test('a warning alone exits 0', () async {
-    for (final path in ['user', 'user_mutations', 'user_subscriptions']) {
+    for (final path in [
+      'user',
+      'stats',
+      'user_mutations',
+      'user_subscriptions',
+    ]) {
       project.file('lib/$path.graphql').deleteSync();
     }
     expect(await project.run(['generate']), 0);
```

In `packages/typed_graphql_codegen/test/cli/project_reading_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -48,7 +48,12 @@ void main() {
   });
 
   test('check with only a warning exits 0 and prints it', () async {
-    for (final path in ['user', 'user_mutations', 'user_subscriptions']) {
+    for (final path in [
+      'user',
+      'stats',
+      'user_mutations',
+      'user_subscriptions',
+    ]) {
       project.file('lib/$path.graphql').deleteSync();
     }
     await project.run(['generate']);
```

In `packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -65,7 +65,7 @@ void main() {
 
   test('generate from a URL writes the files of the SDL project', () async {
     expect(await project.run(['generate'], environment: environment), 0);
-    expect(project.out.toString(), 'Wrote 5 files.\n');
+    expect(project.out.toString(), 'Wrote 6 files.\n');
     expect(project.file('lib/user.graphql.dart').existsSync(), isTrue);
   });
 
```

In `packages/typed_graphql_codegen/test/emit/dart_names_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -55,6 +55,23 @@ void main() {
     );
   });
 
+  test('memberName escapes names that shadow a type or annotation', () {
+    expect(
+      [
+        for (final name in ['int', 'bool', 'double', 'num', 'override'])
+          names.memberName(name, reservedMembers: DartNames.objectMembers),
+      ],
+      [r'int$', r'bool$', r'double$', r'num$', r'override$'],
+    );
+  });
+
+  test('enum values that shadow a type or annotation are escaped', () {
+    expect(
+      names.memberName('bool', reservedMembers: DartNames.enumMembers),
+      r'bool$',
+    );
+  });
+
   test('memberName leaves a member the caller did not reserve', () {
     expect(names.memberName('toJson'), 'toJson');
   });
```

Create `packages/typed_graphql_codegen/test/goldens/operations/input/lib/stats.graphql`:

```graphql
query GetStats($role: Role = ADMIN, $flag: Flag = name) {
  stats(role: $role, flag: $flag) {
    int
    bool
    override
    _hidden
    flag
    matrix {
      id
    }
    summary
  }
}
```

In `packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -34,6 +34,8 @@ input Paging {
   other: String!
   after: Cursor
   client: Int
+  int: Int
+  override: String
 }
 
 input Unreached {
@@ -60,7 +62,24 @@ type Bot implements Node {
 
 union SearchResult = User | Bot
 
+enum Flag {
+  name
+  index
+  values
+}
+
+type Stats {
+  int: Int
+  bool: Boolean
+  override: String
+  _hidden: Int
+  flag: Flag
+  matrix: [[User!]]
+  summary: String
+}
+
 type Query {
+  stats(role: Role, flag: Flag): Stats
   user(id: ID!): User
   node(id: ID!): Node
   search(by: SearchBy!, filter: UserFilter, paging: Paging): [SearchResult!]!
```

In `packages/typed_graphql_codegen/test/goldens/operations/output/build/persisted_operations.json.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -14,6 +14,12 @@
       "type": "query",
       "body": "query FindNode($id:ID!){node(id:$id){id ...on User{name ...UserCard}...on Bot{model}__typename}}fragment UserCard on User{id name}"
     },
+    {
+      "id": "130d1b0f2357cd5e194b7ea4e431a802b93cf8ca9b1eccf000514436908f72ba",
+      "name": "GetStats",
+      "type": "query",
+      "body": "query GetStats($role:Role=ADMIN$flag:Flag=name){stats(role:$role flag:$flag){int bool override _hidden flag matrix{id __typename}summary __typename}}"
+    },
     {
       "id": "198ab8e735cf86b04b66c1094135e3e63cfae5a89e4b793ae58982ff95891f8e",
       "name": "GetUser",
```

In `packages/typed_graphql_codegen/test/goldens/operations/output/lib/schema.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,6 +6,57 @@ import 'package:scalar_codecs/scalar_codecs.dart' as scalar_0;
 import 'package:typed_graphql/typed_graphql.dart' as graphql;
 import 'package:typed_graphql_client/typed_graphql_client.dart' as client;
 
+/// The enum `Flag`.
+sealed class Flag implements client.DataEnum {
+  /// The value named [raw]: a [FlagKnown], or a [FlagUnknown] for a name
+  /// this code does not know.
+  factory Flag.parse(String raw) {
+    for (final value in FlagKnown.values) {
+      if (value.raw == raw) return value;
+    }
+    return FlagUnknown(raw);
+  }
+
+  /// Reads and writes the values of `Flag`.
+  static const client.DataCodec<Flag> codec = client.EnumDataCodec(Flag.parse);
+}
+
+/// The values of [Flag] this code knows.
+enum FlagKnown implements Flag {
+  /// `name`.
+  name$('name'),
+
+  /// `index`.
+  index$('index'),
+
+  /// `values`.
+  values$('values');
+
+  const FlagKnown(this.raw);
+
+  @override
+  final String raw;
+}
+
+/// A value of [Flag] this code does not know, such as one added to the
+/// schema after the code was generated.
+final class FlagUnknown implements Flag {
+  /// Creates the value named [raw].
+  const FlagUnknown(this.raw);
+
+  @override
+  final String raw;
+
+  @override
+  bool operator ==(Object other) => other is FlagUnknown && other.raw == raw;
+
+  @override
+  int get hashCode => raw.hashCode;
+
+  @override
+  String toString() => 'FlagUnknown($raw)';
+}
+
 /// A user role.
 sealed class Role implements client.DataEnum {
   /// The value named [raw]: a [RoleKnown], or a [RoleUnknown] for a name
```

Create `packages/typed_graphql_codegen/test/goldens/operations/output/lib/stats.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/stats.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

import 'schema.graphql.dart';

/// The query `GetStats`.
final class GetStatsQuery extends client.GraphQLQuery<GetStatsData> {
  /// Creates the query with its [variables].
  const GetStatsQuery(this.variables);

  /// The document of `GetStats` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'GetStats',
        type: graphql.OperationType.query,
        text: r'query GetStats($role:Role=ADMIN$flag:Flag=name){stats(role:$role flag:$flag){int bool override _hidden flag matrix{id __typename}summary __typename}}',
        sha256:
          '130d1b0f2357cd5e194b7ea4e431a802b93cf8ca9b1eccf000514436908f72ba',
      );

  /// The variables the query is sent with.
  final GetStatsVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<GetStatsData> decodeData(graphql.JsonObject data) =>
      GetStatsData.decode(data, variables: variablesJson);
}

/// The variables of the query `GetStats`.
final class GetStatsVariables implements client.DataObject {
  /// Creates the variables.
  const GetStatsVariables({
    this.role = const graphql.Optional.absent(),
    this.flag = const graphql.Optional.absent(),
  });

  static const client.DataCodec<Role?> _roleCodec =
      client.NullableDataCodec(Role.codec);

  static const client.DataCodec<Flag?> _flagCodec =
      client.NullableDataCodec(Flag.codec);

  /// The variable `$role`; its default is `ADMIN`.
  final graphql.Optional<Role?> role;

  /// The variable `$flag`; its default is `name`.
  final graphql.Optional<Flag?> flag;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    if (role case graphql.Present(:final value))
      'role': _roleCodec.write(value),
    if (flag case graphql.Present(:final value))
      'flag': _flagCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is GetStatsVariables &&
      other.role == role &&
      other.flag == flag;

  @override
  int get hashCode => Object.hashAll([role.hashCode, flag.hashCode]);

  @override
  String toString() => 'GetStatsVariables(role: $role, flag: $flag)';
}

/// The data of the query `GetStats`.
final class GetStatsData implements client.DataObject {
  /// Creates the data.
  const GetStatsData({this.stats});

  factory GetStatsData._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetStatsData(stats: _statsCodec.field(json, 'stats', context));

  /// Reads and writes the data.
  static const client.DataCodec<GetStatsData> codec =
      client.ObjectDataCodec(GetStatsData._read);

  static const client.DataCodec<GetStatsDataStats?> _statsCodec =
      client.NullableDataCodec(GetStatsDataStats.codec);

  /// The field `stats`.
  final GetStatsDataStats? stats;

  /// Reads [json], the `data` of a response to the query sent with
  /// [variables].
  static graphql.DecodeResult<GetStatsData> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'stats': _statsCodec.write(stats)});

  @override
  bool operator ==(Object other) =>
      other is GetStatsData && other.stats == stats;

  @override
  int get hashCode => stats.hashCode;

  @override
  String toString() => 'GetStatsData(stats: $stats)';
}

/// The field `stats` of [GetStatsData].
final class GetStatsDataStats implements client.DataObject {
  /// Creates the value.
  const GetStatsDataStats({
    this.int$,
    this.bool$,
    this.override$,
    this.$hidden,
    this.flag,
    this.matrix,
    this.summary,
  });

  factory GetStatsDataStats._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetStatsDataStats(
    int$: _int$Codec.field(json, 'int', context),
    bool$: _bool$Codec.field(json, 'bool', context),
    override$: _override$Codec.field(json, 'override', context),
    $hidden: _$hiddenCodec.field(json, '_hidden', context),
    flag: _flagCodec.field(json, 'flag', context),
    matrix: _matrixCodec.field(json, 'matrix', context),
    summary: _summaryCodec.field(json, 'summary', context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<GetStatsDataStats> codec =
      client.ObjectDataCodec(GetStatsDataStats._read);

  static const client.DataCodec<int?> _int$Codec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.IntCodec()));

  static const client.DataCodec<bool?> _bool$Codec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.BooleanCodec()));

  static const client.DataCodec<String?> _override$Codec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  static const client.DataCodec<int?> _$hiddenCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.IntCodec()));

  static const client.DataCodec<Flag?> _flagCodec =
      client.NullableDataCodec(Flag.codec);

  static const client.DataCodec<List<List<GetStatsDataStatsMatrix>?>?> _matrixCodec =
      client.NullableDataCodec(
        client.ListDataCodec(
          client.NullableDataCodec(
            client.ListDataCodec(GetStatsDataStatsMatrix.codec),
          ),
        ),
      );

  static const client.DataCodec<String?> _summaryCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  /// The field `int`.
  final int? int$;

  /// The field `bool`.
  final bool? bool$;

  /// The field `override`.
  final String? override$;

  /// The field `_hidden`.
  final int? $hidden;

  /// The field `flag`.
  final Flag? flag;

  /// The field `matrix`.
  final List<List<GetStatsDataStatsMatrix>?>? matrix;

  /// The field `summary`.
  final String? summary;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'int': _int$Codec.write(int$),
    'bool': _bool$Codec.write(bool$),
    'override': _override$Codec.write(override$),
    '_hidden': _$hiddenCodec.write($hidden),
    'flag': _flagCodec.write(flag),
    'matrix': _matrixCodec.write(matrix),
    'summary': _summaryCodec.write(summary),
  });

  @override
  bool operator ==(Object other) =>
      other is GetStatsDataStats &&
      other.int$ == int$ &&
      other.bool$ == bool$ &&
      other.override$ == override$ &&
      other.$hidden == $hidden &&
      other.flag == flag &&
      const client.DataEquality().equals(other.matrix, matrix) &&
      other.summary == summary;

  @override
  int get hashCode => Object.hashAll([
    int$,
    bool$,
    override$,
    $hidden,
    flag,
    const client.DataEquality().hash(matrix),
    summary,
  ]);

  @override
  String toString() =>
      'GetStatsDataStats(int\$: ${int$}, bool\$: ${bool$}, override\$: ${override$}, \$hidden: ${$hidden}, flag: $flag, matrix: $matrix, summary: $summary)';
}

/// The items of the field `matrix` of [GetStatsDataStats].
final class GetStatsDataStatsMatrix implements client.DataObject {
  /// Creates the value.
  const GetStatsDataStatsMatrix({required this.id});

  factory GetStatsDataStatsMatrix._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetStatsDataStatsMatrix(id: _idCodec.field(json, 'id', context));

  /// Reads and writes the value.
  static const client.DataCodec<GetStatsDataStatsMatrix> codec =
      client.ObjectDataCodec(GetStatsDataStatsMatrix._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The field `id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({'id': _idCodec.write(id)});

  @override
  bool operator ==(Object other) =>
      other is GetStatsDataStatsMatrix && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GetStatsDataStatsMatrix(id: $id)';
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_test.dart test/cli/project_reading_test.dart test/cli/schema_fetcher_test.dart test/emit/dart_names_test.dart)
```

Expected: FAIL. The new and changed tests fail on the behaviour this task fixes (assertion failures; a test that uses a name the next step adds does not compile).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,8 +8,19 @@ final class DartNames {
   /// Creates the name converter.
   const DartNames();
 
+  // Bare identifiers the generated members use as types or annotations: a
+  // member of the same name would shadow them inside the class.
+  static const Set<String> _shadowable = <String>{
+    'int',
+    'bool',
+    'double',
+    'num',
+    'override',
+  };
+
   /// Members every generated data or input class has.
   static const Set<String> objectMembers = <String>{
+    ..._shadowable,
     'hashCode',
     'runtimeType',
     'toString',
@@ -25,6 +36,7 @@ final class DartNames {
 
   /// Members every generated enum has, including those of `Enum`.
   static const Set<String> enumMembers = <String>{
+    ..._shadowable,
     'hashCode',
     'runtimeType',
     'toString',
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_test.dart test/cli/project_reading_test.dart test/cli/schema_fetcher_test.dart test/emit/dart_names_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_codegen/lib/src/emit/dart_names.dart packages/typed_graphql_codegen/test/cli/codegen_command_test.dart packages/typed_graphql_codegen/test/cli/project_reading_test.dart packages/typed_graphql_codegen/test/cli/schema_fetcher_test.dart packages/typed_graphql_codegen/test/emit/dart_names_test.dart packages/typed_graphql_codegen/test/goldens/operations/input/lib/stats.graphql packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql packages/typed_graphql_codegen/test/goldens/operations/output/build/persisted_operations.json.golden packages/typed_graphql_codegen/test/goldens/operations/output/lib/schema.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/operations/output/lib/stats.graphql.dart.golden
git commit -q -m "fix(typed_graphql_codegen): suffix field names that shadow a type or annotation" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: Backtick angle brackets in generated doc comments

Final review, Important 2: a schema description such as `Returns a List<User>` tripped `unintended_html_in_doc_comment` in the user's analysis of the generated code. `DocCommentEscaper` wraps each angle bracket pair outside a code span or fence in backticks, and `DartWriter.doc` uses it; the golden description holds angle brackets, brackets, a dollar sign, quotes, a backslash and a comment end.

Commit on the branch: `3ec5710`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/emit/doc_comment_escaper.dart`
- Modify: `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart`
- Test: `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart`, `packages/typed_graphql_codegen/test/emit/doc_comment_escaper_test.dart`, `packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql`, `packages/typed_graphql_codegen/test/goldens/operations/output/lib/stats.graphql.dart.golden`

**Interfaces:**
- Consumes: M10b `DartWriter`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// emit/doc_comment_escaper.dart
final class DocCommentEscaper
  const DocCommentEscaper()
  String escape(String line)
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -36,6 +36,15 @@ void main() {
     );
   });
 
+  test('doc backticks angle brackets outside a fence only', () {
+    final DartWriter writer = DartWriter();
+    writer.doc('A List<User>.\n```graphql\nList<User>\n```');
+    expect(
+      writer.text,
+      '/// A List`<User>`.\n/// ```graphql\n/// List<User>\n/// ```\n',
+    );
+  });
+
   test('doc keeps a fence that already has a language', () {
     final DartWriter writer = DartWriter();
     writer.doc('```dart\nx\n```');
````

Create `packages/typed_graphql_codegen/test/emit/doc_comment_escaper_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/doc_comment_escaper.dart';

void main() {
  const escaper = DocCommentEscaper();

  const cases = <String, String>{
    'Returns a List<User>.': 'Returns a List`<User>`.',
    'Map<String, List<User>> nested': 'Map`<String, List<User>>` nested',
    '<b>bold</b>': '`<b>`bold`</b>`',
    'Already `List<User>` quoted': 'Already `List<User>` quoted',
    'a < b and c': 'a < b and c',
    r'Plain [x] with $5 and */': r'Plain [x] with $5 and */',
    'Unclosed <User': 'Unclosed <User',
  };

  for (final MapEntry(key: input, value: expected) in cases.entries) {
    test('escape of $input', () => expect(escaper.escape(input), expected));
  }
}
```

In `packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -75,6 +75,7 @@ type Stats {
   _hidden: Int
   flag: Flag
   matrix: [[User!]]
+  "Returns a List<User> of [x] costing $5, 'quoted', \\ and */ closed."
   summary: String
 }
 
```

In `packages/typed_graphql_codegen/test/goldens/operations/output/lib/stats.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -194,7 +194,7 @@ final class GetStatsDataStats implements client.DataObject {
   /// The field `matrix`.
   final List<List<GetStatsDataStatsMatrix>?>? matrix;
 
-  /// The field `summary`.
+  /// Returns a List`<User>` of [x] costing $5, 'quoted', \ and */ closed.
   final String? summary;
 
   @override
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/dart_writer_test.dart test/emit/doc_comment_escaper_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -1,3 +1,5 @@
+import 'doc_comment_escaper.dart';
+
 /// A text builder for generated Dart code.
 ///
 /// {@category codegen}
@@ -54,6 +56,10 @@ final class DartWriter {
 
   String _docLine(String content) {
     final String trimmed = content.trim();
+    if (!_isInFence && !trimmed.startsWith('```')) {
+      // Descriptions come from the schema; see [DocCommentEscaper].
+      return _docText(const DocCommentEscaper().escape(content));
+    }
     if (trimmed.startsWith('```')) {
       if (_isInFence) {
         _isInFence = false;
@@ -64,9 +70,11 @@ final class DartWriter {
         }
       }
     }
-    return content.isEmpty ? '///' : '/// $content';
+    return _docText(content);
   }
 
+  String _docText(String content) => content.isEmpty ? '///' : '/// $content';
+
   /// Writes `open + items.join(', ') + close` on one line when it fits in 80
   /// columns, otherwise one item per line, each ending with `,`.
   void items(String open, List<String> items, String close) {
````

Create `packages/typed_graphql_codegen/lib/src/emit/doc_comment_escaper.dart`:

```dart
/// Makes schema text safe inside a `///` comment.
///
/// `unintended_html_in_doc_comment` (in `package:lints`) reports an angle
/// bracket pair such as `List<User>` outside code, so the generated code would
/// fail its user's analysis. This wraps each such pair in backticks.
///
/// {@category codegen}
final class DocCommentEscaper {
  /// Creates the escaper.
  const DocCommentEscaper();

  /// [line] with every `<...>` outside a code span wrapped in backticks.
  String escape(String line) {
    if (!line.contains('<')) {
      return line;
    }
    final StringBuffer out = StringBuffer();
    bool isInCode = false;
    int index = 0;
    while (index < line.length) {
      final String character = line[index];
      if (character == '`') {
        isInCode = !isInCode;
      }
      final int end = isInCode || character != '<'
          ? -1
          : _closingBracket(line, index);
      if (end < 0) {
        out.write(character);
        index++;
      } else {
        out.write('`${line.substring(index, end + 1)}`');
        index = end + 1;
      }
    }
    return out.toString();
  }

  /// The index of the `>` that closes the `<` at [start], or -1 when the
  /// bracket opens no pair or holds a backtick (which would end the span).
  int _closingBracket(String line, int start) {
    int depth = 0;
    for (int index = start; index < line.length; index++) {
      final String character = line[index];
      if (character == '`') {
        return -1;
      }
      if (character == '<') {
        depth++;
      } else if (character == '>') {
        depth--;
        if (depth == 0) {
          return index;
        }
      }
    }
    return -1;
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/dart_writer_test.dart test/emit/doc_comment_escaper_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart packages/typed_graphql_codegen/lib/src/emit/doc_comment_escaper.dart packages/typed_graphql_codegen/test/emit/dart_writer_test.dart packages/typed_graphql_codegen/test/emit/doc_comment_escaper_test.dart packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql packages/typed_graphql_codegen/test/goldens/operations/output/lib/stats.graphql.dart.golden
git commit -q -m "fix(typed_graphql_codegen): backtick angle brackets in generated doc comments" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: Say everything GQL501, GQL504 and GQL510 report

Final review, Important 3: the catalog comments and the guide rows of `GQL501` (globs and schema URL headers), `GQL504` (fragment spreads through other fragments) and `GQL510` (listing the documents glob and writing a generated file) say what the code reports.

Commit on the branch: `1d6be79`.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql_codegen/doc/client_codegen.md`

**Interfaces:**
- Consumes: Tasks 1-8.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -515,8 +515,10 @@ enum DiagnosticCode(
   /// the YAML parser's.
   configSyntax('GQL500'),
 
-  /// `GQL501`: a missing, unknown or mistyped key, or a malformed path or Dart
-  /// reference, in the code generator's configuration.
+  /// `GQL501`: a missing, unknown or mistyped key, or a malformed path, glob
+  /// or Dart reference, in the code generator's configuration; also a schema
+  /// URL header whose `${NAME}` variable is not set or is empty, or whose
+  /// expanded value is not ASCII.
   invalidConfig('GQL501'),
 
   /// `GQL502`: a schema file the code generator cannot read as a schema: not
@@ -529,9 +531,10 @@ enum DiagnosticCode(
 
   /// `GQL504`: a construct the code generator does not support yet: `@defer`,
   /// `@stream`, an introspection field (`__schema`, `__type`), or a
-  /// subscription root that spreads (directly or inside an inline fragment) a
-  /// fragment which plans as a sealed base class; it would need `__typename`,
-  /// which a subscription cannot select. A plain inline fragment is fine.
+  /// subscription root that spreads a fragment which plans as a sealed base
+  /// class, directly, inside an inline fragment or through other fragment
+  /// spreads; it would need `__typename`, which a subscription cannot select.
+  /// A plain inline fragment is fine.
   unsupportedInDocument('GQL504'),
 
   /// `GQL505`: the configuration maps a scalar the schema does not have as a
@@ -557,9 +560,11 @@ enum DiagnosticCode(
   /// what `generate` would write; reported without a span.
   outputOutdated('GQL509'),
 
-  /// `GQL510`: a file the command line must read, such as the configuration,
-  /// the schema or a document, or the schema URL, cannot be read; reported
-  /// without a span.
+  /// `GQL510`: the command line cannot read a file it needs (the
+  /// configuration, the schema or a document), list the documents glob, fetch
+  /// the schema URL (a network failure, a timeout, a redirect, a body over
+  /// 64 MiB, a non-success status or an unreadable body), or write a generated
+  /// file; reported without a span.
   inputUnreadable('GQL510'),
 
   /// `GQL511`: an operation or fragment whose selections would make the code
```

- [ ] **Step 2: Update the documents**

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -898,7 +898,7 @@ and are never reused.
 | Code | Severity | Reported when |
 |---|---|---|
 | `GQL500` | error | `typed_graphql.yaml` is not valid YAML. |
-| `GQL501` | error | A configuration key is missing, unknown or mistyped, or a path or Dart reference is malformed. |
+| `GQL501` | error | A configuration key is missing, unknown or mistyped, or a path, glob or Dart reference is malformed; or a schema URL header uses a `${NAME}` variable that is not set or is empty, or expands to a value that is not ASCII. |
 | `GQL502` | error | The schema file is not JSON, or is JSON that is not an object, when it should be an introspection result. |
 | `GQL503` | error | An operation has no name; the generated classes are named after the operation. |
 | `GQL504` | error | A document uses `@defer` or `@stream`, or selects an introspection field (`__schema`, `__type`), which the generator does not support yet; or a subscription spreads, at its root, a fragment that becomes a sealed class (directly or through other fragments or inline fragments): the sealed class would need `__typename` there, and a subscription cannot select it. |
@@ -907,7 +907,7 @@ and are never reused.
 | `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`), a class of an operation and a fragment, two members of one class (such as the fields `user_name` and `userName`, or two fragments `UserCard` and `userCard`), or two files at one path. |
 | `GQL508` | error | A name the generator would declare hides a Dart type the generated code uses, such as `List`, or a `dart:core` type a scalar is mapped to. |
 | `GQL509` | error | `check` found a generated file that is missing or differs from what `generate` would write. |
-| `GQL510` | error | The command line cannot read the configuration, the schema file, a document or the schema URL (a network failure, a timeout, a redirect, a body over 64 MiB, a non-success status or an unreadable body). |
+| `GQL510` | error | The command line cannot read the configuration, the schema file or a document, cannot list the documents glob, cannot fetch the schema URL (a network failure, a timeout, a redirect, a body over 64 MiB, a non-success status or an unreadable body), or cannot write a generated file. |
 | `GQL511` | error | An operation or fragment would generate more than 10000 classes, for instance a selection on an interface that reaches many types, repeated under many aliases. |
 
 The problems of the schema and of the documents keep the codes of the core:
```

- [ ] **Step 3: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql_codegen/doc/client_codegen.md
git commit -q -m "docs(typed_graphql): say in the catalog and the guide everything GQL501, GQL504 and GQL510 report" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 13: Keep user files from the command line's side effects

Final review minors 8, 11 and 12: the temporary file of a write lives in its own folder, so a user file named like the target plus `.tmp` is not overwritten; a documents glob whose brace alternative reaches outside the project is `GQL501`; a single written file prints `Wrote 1 file.`.

Commit on the branch: `56caa10`.

**Files:**
- Modify: `packages/typed_graphql_codegen/doc/client_codegen.md`, `packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart`, `packages/typed_graphql_codegen/lib/src/cli/output_writer.dart`, `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`
- Test: `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`, `packages/typed_graphql_codegen/test/cli/output_writer_test.dart`, `packages/typed_graphql_codegen/test/cli/project_reading_test.dart`

**Interfaces:**
- Consumes: Task 8 `OutputWriter` and `ProjectReader`.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/cli/codegen_command_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -32,6 +32,13 @@ void main() {
     }
   });
 
+  test('a generate that writes one file says so in the singular', () async {
+    await project.run(['generate']);
+    project.file(generated).writeAsStringSync('// edited\n');
+    expect(await project.run(['generate']), 0);
+    expect(project.out.toString(), 'Wrote 1 file.\n');
+  });
+
   test('a second generate writes nothing', () async {
     await project.run(['generate']);
     expect(await project.run(['generate']), 0);
```

In `packages/typed_graphql_codegen/test/cli/output_writer_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -36,7 +36,21 @@ void main() {
     expect(result.problems.map((d) => d.toString()), [
       startsWith("error GQL510: Cannot write 'lib/a.dart': "),
     ]);
-    expect(File('${directory.path}/lib/a.dart.tmp').existsSync(), isFalse);
+    expect(
+      [
+        for (final entity in Directory('${directory.path}/lib').listSync())
+          entity.path,
+      ]..sort(),
+      ['${directory.path}/lib/a.dart', '${directory.path}/lib/b.dart'],
+    );
+  });
+
+  test('write keeps a user file named like a fixed temporary name', () {
+    File('${directory.path}/lib/a.dart.tmp')
+      ..createSync(recursive: true)
+      ..writeAsStringSync('mine');
+    writer.write([file]);
+    expect(File('${directory.path}/lib/a.dart.tmp').readAsStringSync(), 'mine');
   });
 
   test('an output that is not UTF-8 is replaced by write', () {
```

In `packages/typed_graphql_codegen/test/cli/project_reading_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -30,6 +30,21 @@ void main() {
     );
   });
 
+  test('a brace alternative that leaves the project is GQL501', () async {
+    final outside = File('${project.directory.parent.path}/m10_outside.graphql')
+      ..writeAsStringSync('query Outside { __typename }');
+    addTearDown(outside.deleteSync);
+    documents('"{..,lib}/m10_outside.graphql"');
+    expect(await project.run(['generate']), 1);
+    expect(
+      project.err.toString(),
+      startsWith(
+        "error GQL501: The documents pattern '{..,lib}/m10_outside.graphql' "
+        'matches a file outside the project.',
+      ),
+    );
+  });
+
   test('a symbolic link to a document is not followed', () async {
     final outside = File('${project.directory.path}/outside.txt')
       ..writeAsStringSync('query Outside { __typename }');
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_test.dart test/cli/output_writer_test.dart test/cli/project_reading_test.dart)
```

Expected: FAIL. The new and changed tests fail on the behaviour this task fixes (assertion failures; a test that uses a name the next step adds does not compile).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -99,9 +99,11 @@ final class CodegenCommand {
     }
     final (:written, :problems) = writer.write(result.files);
     final code = _report([...result.diagnostics, ...problems], secrets);
-    out.writeln(
-      written.isEmpty ? 'Nothing to write.' : 'Wrote ${written.length} files.',
-    );
+    out.writeln(switch (written.length) {
+      0 => 'Nothing to write.',
+      1 => 'Wrote 1 file.',
+      final count => 'Wrote $count files.',
+    });
     return code;
   }
 
```

In `packages/typed_graphql_codegen/lib/src/cli/output_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -76,13 +76,15 @@ final class const OutputWriter(
   void _replace(GeneratedFile generated) {
     final file = File(p.join(directory, generated.path));
     file.parent.createSync(recursive: true);
-    final temporary = File('${file.path}.tmp');
+    // A folder of its own: a fixed name next to the target could overwrite
+    // a file of the user's.
+    final folder = file.parent.createTempSync('.typed_graphql_');
     try {
+      final temporary = File(p.join(folder.path, 'output'));
       temporary.writeAsStringSync(generated.text);
       temporary.renameSync(file.path);
-    } on FileSystemException {
-      if (temporary.existsSync()) temporary.deleteSync();
-      rethrow;
+    } finally {
+      folder.deleteSync(recursive: true);
     }
   }
 
```

In `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -124,9 +124,14 @@ final class ProjectReader {
         );
         for (final entity in entities) {
           if (entity is! File || !entity.path.endsWith('.graphql')) continue;
-          final relative = p.posix.joinAll(
-            p.split(p.relative(entity.path, from: directory)),
-          );
+          final parts = p.split(p.relative(entity.path, from: directory));
+          if (parts.first == '..') {
+            // A brace alternative such as `{..,lib}` passes the path rule,
+            // which only checks whole segments.
+            problems.add(_leavesProject(pattern));
+            break;
+          }
+          final relative = p.posix.joinAll(parts);
           if (relative != schemaPath) paths.add(relative);
         }
       } on FormatException catch (error) {
@@ -149,6 +154,12 @@ final class ProjectReader {
     return (paths: paths.toList()..sort(), problems: problems);
   }
 
+  Diagnostic _leavesProject(String pattern) => Diagnostic(
+    .invalidConfig,
+    .error,
+    "The documents pattern '$pattern' matches a file outside the project.",
+  );
+
   _FileOutcome _readText(String path) {
     try {
       return _FileText(File(p.join(directory, path)).readAsStringSync());
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/cli/codegen_command_test.dart test/cli/output_writer_test.dart test/cli/project_reading_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -181,7 +181,7 @@ relative to the file's folder. `--help` prints the usage.
 `generate` reads the configuration, the schema and the documents, runs the
 checks and, when there is no error, writes each generated file whose text
 differs from what is on disk (creating folders as needed). It prints
-`Wrote N files.` or `Nothing to write.` and never deletes a file: a library
+`Wrote N files.` (`Wrote 1 file.` for one) or `Nothing to write.` and never deletes a file: a library
 whose document you removed stays until you delete it, and neither `generate`
 nor `check` looks at it, so `check` can be clean while a stale library is
 still compiled. A file is written through a temporary file and a rename; a
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/lib/src/cli/codegen_command.dart packages/typed_graphql_codegen/lib/src/cli/output_writer.dart packages/typed_graphql_codegen/lib/src/cli/project_reader.dart packages/typed_graphql_codegen/test/cli/codegen_command_test.dart packages/typed_graphql_codegen/test/cli/output_writer_test.dart packages/typed_graphql_codegen/test/cli/project_reading_test.dart
git commit -q -m "fix(typed_graphql_codegen): keep user files from the command line's side effects" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 14: Split the documents listing into named steps

A refactoring of Task 13's `ProjectReader._documentPaths` that moves the collection of the matched documents into `_collect`, so the method and its nesting stay within the code rules. No behaviour changes.

Commit on the branch: `13a7df1`.

**Files:**
- Modify: `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`

**Interfaces:**
- Consumes: Task 13.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/cli/project_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -122,17 +122,8 @@ final class ProjectReader {
           root: directory,
           followLinks: false,
         );
-        for (final entity in entities) {
-          if (entity is! File || !entity.path.endsWith('.graphql')) continue;
-          final parts = p.split(p.relative(entity.path, from: directory));
-          if (parts.first == '..') {
-            // A brace alternative such as `{..,lib}` passes the path rule,
-            // which only checks whole segments.
-            problems.add(_leavesProject(pattern));
-            break;
-          }
-          final relative = p.posix.joinAll(parts);
-          if (relative != schemaPath) paths.add(relative);
+        if (!_collect(entities, schemaPath, paths)) {
+          problems.add(_leavesProject(pattern));
         }
       } on FormatException catch (error) {
         problems.add(
@@ -154,6 +145,25 @@ final class ProjectReader {
     return (paths: paths.toList()..sort(), problems: problems);
   }
 
+  /// Adds the documents among [entities] to [paths]; false when one lies
+  /// outside the project.
+  bool _collect(
+    List<FileSystemEntity> entities,
+    String schemaPath,
+    Set<String> paths,
+  ) {
+    for (final entity in entities) {
+      if (entity is! File || !entity.path.endsWith('.graphql')) continue;
+      final parts = p.split(p.relative(entity.path, from: directory));
+      // A brace alternative such as `{..,lib}` passes the path rule, which
+      // only checks whole segments.
+      if (parts.first == '..') return false;
+      final relative = p.posix.joinAll(parts);
+      if (relative != schemaPath) paths.add(relative);
+    }
+    return true;
+  }
+
   Diagnostic _leavesProject(String pattern) => Diagnostic(
     .invalidConfig,
     .error,
```

- [ ] **Step 2: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add packages/typed_graphql_codegen/lib/src/cli/project_reader.dart
git commit -q -m "refactor(typed_graphql_codegen): split the documents listing into named steps" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 15: Describe the generated-code contract and update the M10 texts

Final review minors 4, 5 and 6: the codegen library doc names operations, fragments and the manifest, the root README no longer calls the client a skeleton, `CLAUDE.md` says that `GQL506` comes from `ClientProjectLoader` and gains a paragraph on the generated-code contract of `typed_graphql_client`.

Commit on the branch: `a5948ea`.

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`

**Interfaces:**
- Consumes: Tasks 1-13.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,9 +1,11 @@
 /// The typed_graphql code generator and its CLI: Dart client code from .graphql
 /// operations and SDL-first server code, without the analyzer.
 ///
-/// Under construction: so far the package reads `typed_graphql.yaml`
-/// ([CodegenConfig]) and [ClientGenerator] writes the Dart enums and input
-/// objects of the schema; see the package README.
+/// Under construction: the package reads `typed_graphql.yaml`
+/// ([CodegenConfig]) and [ClientGenerator] writes the Dart for a schema's
+/// enums and input objects, for operations and fragments, and the persisted
+/// operations manifest. The command line is `bin/typed_graphql_codegen.dart`;
+/// see the package README.
 library;
 
 export 'src/config/codegen_config.dart';
```

- [ ] **Step 2: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -413,9 +413,10 @@ and `GeneratedFile`s.
 - `generator/`: `ClientGenerator(config)` has `rules` (the specified rules
   minus the unused-fragment and lone-anonymous ones, plus `GQL503` named
   operations, `GQL504` unsupported `@defer`/`@stream`/`__schema`/`__type` and
-  a subscription whose root fragment becomes a sealed class, and `GQL506` no
-  document as a warning), `check` and `generate` (`GenerationResult`: diagnostics
-  and files; an error means no files). It also checks the scalar mappings
+  a subscription whose root fragment becomes a sealed class), `check` and
+  `generate` (`GenerationResult`: diagnostics and files; an error means no
+  files). `GQL506` (no document, a warning) comes from `ClientProjectLoader`,
+  not from a rule. It also checks the scalar mappings
   (`GQL505`), the names (`GQL507` a Dart name declared twice, also members
   and paths; `GQL508` a name that hides a Dart type the code uses) and the
   size (`GQL511`, 10000 classes per operation or fragment).
@@ -448,6 +449,17 @@ and `GeneratedFile`s.
   byte. `example/` is a workspace member with its own `pubspec.yaml`
   (`publish_to: none`) because the generated code imports the client.
 
+**Client contract** (`typed_graphql_client/lib/src/operation/`; M10). What
+generated code imports. `GraphQLOperation` (query, mutation, subscription)
+carries an `OperationDocument` (text, sha256) and `decodeData`. A data class
+reads itself through a `DataCodec<T>` constant composed of `ObjectDataCodec`,
+`ListDataCodec`, `NullableDataCodec`, `ScalarDataCodec`, `EnumDataCodec`
+(a `DataEnum` is a known or unknown value) and `JsonDataCodec` (an unmapped
+scalar); `read` throws `DataFormatException`, `decode` turns it into a
+`DecodeFailure`. `DataContext.flag` answers `@include`/`@skip` variables,
+`DataEquality` compares lists and `Optional`s by value, and `JsonMerger`
+merges what a class and its fragments write for one object.
+
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
 `ArgumentError`, `RangeError`, `StateError`.
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -112,7 +112,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
 | [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
-| [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
+| [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | under construction (the generated-code contract, M10; the rest M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
 | [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
 | [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language, schema and introspection suites, fuzzers (M2, M3) |
```

- [ ] **Step 3: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add CLAUDE.md README.md packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart
git commit -q -m "docs: describe the generated-code contract and bring the M10 texts up to date" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 16: Record that M10 is complete and awaits merge

The handoff says M10 is complete on branch `m10-final` with the final opus review done, awaiting merge, and that the client's Chrome runs are deferred to M11.

Commit on the branch: `21c31fd`.

**Files:**
- Modify: `docs/superpowers/HANDOFF.md`

**Interfaces:**
- Consumes: Tasks 1-14.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Update the documents**

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 # Handoff: where typed_graphql stands and how to continue
 
-Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a and M4b merged too; M10 on branch `m10-final` pending the final whole-branch review; local `main` is ahead of `origin/main`, push needs the owner's yes). Read this
+Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a and M4b merged too; M10 complete on branch `m10-final`, awaiting merge (not merged); local `main` is ahead of `origin/main`, push needs the owner's yes). Read this
 first on a new device or in a new Claude session. Session memory and scratch
 directories do not travel; this file and the repository hold everything
 needed.
@@ -16,7 +16,7 @@ needed.
 | M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
-| M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is implemented on branch `m10-final`, pending the final whole-branch review; not merged and not pushed (the plans are generated from the commits; the review's fix commits are appended to the M10d plan when it is regenerated). `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
+| M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is complete on branch `m10-final`: the final opus whole-branch review is done and its fix round is committed; awaiting merge, not merged and not pushed (the plans are generated from the commits; the fix round's commits are in the M10d plan). The client's Chrome test runs are deferred to M11. `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
 
 **Decisions (2026-10-14):**
 - Layer order is diagnostics < language < protocol < schema < validation; the
```

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add docs/superpowers/HANDOFF.md
git commit -q -m "docs: record that M10 is complete and awaits merge" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

With the choice this plan makes (`.superpowers/m10-open-questions.md`; the spec's section 17 lists all twelve with recommendations):

- Question 6: `${NAME}` in header values only, expanded by the CLI; an unset or empty variable is `GQL501`; values are replaced by `***` in everything printed.
- Plain `http://` schema URLs are accepted without a warning (documented in the guide).
- `check` and `generate` ignore generated files whose document was removed; the CLI never deletes a file.

## Self-review

- Spec coverage: section 12 (Tasks 2, 4, 8), section 2 "the engine has no `dart:io`" (Task 3), section 13 (Tasks 5, 9), section 14 (Task 5's byte-for-byte example test), the codes `GQL509`, `GQL510` (Task 1).
- Every code block in this plan is the content of a commit that passed the green check; no placeholder remains.
- Type consistency: each task's Produces block is extracted from its commit, and later tasks consume those names.

## After the plan

The final whole-branch review (opus) of `57f85e8..m10-final`, one fix round (its commits are appended to this plan when it is regenerated), then the merge into `main` as the handoff's "How a stage is done" says.
