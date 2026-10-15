# M10a Codegen Front End Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The front end of `packages/typed_graphql_codegen`: `CodegenConfig` read from `typed_graphql.yaml` (R7.1; `GQL500`, `GQL501`), `SchemaLoader` (SDL or an introspection result, validated; `GQL502`), `ProjectDocuments` (every document as one fragment graph with diagnostics at `file:line:col`, R7.2), the codegen validation rules and `ClientGenerator.check` (`GQL503`-`GQL506`), the Client Code Generation guide, and the fixes of the M10a review.

**Architecture:** The engine reads no file. `CodegenConfig.parse(text, path:)` returns the sealed `ConfigResult`; `SchemaLoader.load` takes a `ProjectFile` and returns a `SchemaLoadResult` holding a `ValidSchema` or diagnostics; `ProjectDocuments.read(files)` parses each file alone (its own `Source`, the parser's limits per file), parses the files joined in path order once more as the project document (token limit off) and keeps a `ProjectSourceMap` that turns every diagnostic back into its file's place. `ClientGenerator(config).check(schemaFile, documents)` runs the core `DocumentValidator` with `ClientGenerator.rules` (the specified rules minus `NoUnusedFragmentsRule` and `LoneAnonymousOperationRule`, plus `NamedOperationsRule` and `UnsupportedDirectivesRule`) and `ScalarMappingChecker`.

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, null-aware elements, patterns, sealed classes, records), `package:test`, `package:meta`; in the codegen package `yaml`, `crypto`, `path`, and in its command line `args`, `glob` and `dart:io`. No `analyzer`, no `dart_style`, no `package:gql`.

**Spec:** `docs/superpowers/specs/2026-10-15-m10-client-codegen-design.md` (sections 1-5, 9, 10, 13), section 6 "Client" of `docs/superpowers/specs/2026-10-13-typed-graphql-design.md`, `docs/requirements.md` R7.1, R7.2, R0.3.

**Base:** `main` at `57f85e8` (M4 merged); the spec commit `6f03a9a` first. Work on the branch `m10-final` in a worktree. Every task's code is the content of one commit on that branch, made in this order with the green check after each; one exception to the history order: M10b Task 1 (`b7299f1`, `Optional` in the core) was committed between Tasks 6 and 7 of this plan, and touches no file this plan touches, so the plans list it where it belongs. M10b (`2026-10-15-m10b-runtime-and-schema-types.md`) follows.

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

The inputs most likely to bite a user, each pinned by a named test:

1. Hostile YAML is a diagnostic, never a throw: invalid YAML and a duplicate key (Task 1, `codegen_config_test.dart` "invalid YAML is a GQL500 at its place", "a duplicate key is a GQL500"); an alias value and a non-string key (Task 7, "a YAML alias value is a string error, not a throw", "a non-string key is reported, not thrown").
2. Header injection: a header value with a control character is `GQL501` (Task 7, `codegen_config_test.dart` "a header value with a control character"); the URL scheme check is case-insensitive and rejects other schemes (Task 7, "an upper-case HTTPS scheme is a URL", "another scheme is not a path").
3. Size limits per file, not per project: one file over the token limit fails, two files of 10000 tokens each pass (Task 3, `project_documents_test.dart` "a file over the token limit fails with the token limit code", "two files of 10000 tokens each succeed"); an empty or comment-only file adds nothing (Task 7, "an empty file and a comment-only file add no definition").
4. A schema file that is JSON but not an introspection result, or nested past the reader's depth: Task 2, `schema_loader_test.dart` "an object without __schema is reported at the file"; Task 7, "a JSON nested past the depth limit is reported with the depth limit".
5. The engine stays free of `dart:io`: Task 5, `engine_imports_test.dart` "no library outside lib/src/cli imports dart:io".

## File map

| File | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql_codegen/lib/src/config/codegen_config.dart` | The settings of `typed_graphql.yaml` (R7.1), read by [parse] | 1 |
| `packages/typed_graphql_codegen/lib/src/config/config_draft.dart` | The values read so far from a configuration, with the defaults of the keys not met yet | 1 |
| `packages/typed_graphql_codegen/lib/src/config/config_reader.dart` | Turns the text of `typed_graphql.yaml` into a [ConfigResult] | 1 |
| `packages/typed_graphql_codegen/lib/src/config/config_report.dart` | Collects the `GQL501` problems of one configuration read, in the order the reader meets the nodes | 1 |
| `packages/typed_graphql_codegen/lib/src/config/config_result.dart` | The outcome of [CodegenConfig.parse] | 1 |
| `packages/typed_graphql_codegen/lib/src/config/dart_reference.dart` | A Dart declaration the configuration names, such as the type or the codec of a scalar | 1 |
| `packages/typed_graphql_codegen/lib/src/config/dart_reference_reader.dart` | Reads a [DartReference] written as `<library>#<Name>` or, for a `dart:core` type, as its bare name | 1 |
| `packages/typed_graphql_codegen/lib/src/config/header_reader.dart` | Reads the `headers` map | 1 |
| `packages/typed_graphql_codegen/lib/src/config/relative_path.dart` | Reads a path of the configuration | 1 |
| `packages/typed_graphql_codegen/lib/src/config/scalar_mapping.dart` | How generated code holds a custom scalar (R7.8) | 1 |
| `packages/typed_graphql_codegen/lib/src/config/scalar_mapping_reader.dart` | Reads the `scalars` map | 1 |
| `packages/typed_graphql_codegen/lib/src/config/schema_location.dart` | Where the generator finds the schema (R7.1) | 1 |
| `packages/typed_graphql_codegen/lib/src/config/schema_location_reader.dart` | Reads the `schema` value | 1 |
| `packages/typed_graphql_codegen/test/config/codegen_config_test.dart` | Tests | 1 |
| `packages/typed_graphql_codegen/test/config/scalar_config_test.dart` | Tests | 1 |
| `packages/typed_graphql_codegen/lib/src/project/project_file.dart` | A file of the project the engine reads | 2 |
| `packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart` | Reads the text of an introspection result into a schema build | 2 |
| `packages/typed_graphql_codegen/lib/src/schema/schema_load_result.dart` | The outcome of [SchemaLoader.load] | 2 |
| `packages/typed_graphql_codegen/lib/src/schema/schema_loader.dart` | Reads the schema file of a project | 2 |
| `packages/typed_graphql_codegen/test/schema/schema_loader_test.dart` | Tests | 2 |
| `packages/typed_graphql_codegen/lib/src/documents/project_documents.dart` | The project's `.graphql` files read as one document, so that a fragment is visible from every operation (R7.2) | 3 |
| `packages/typed_graphql_codegen/lib/src/documents/project_documents_result.dart` | The result of reading the project's documents | 3 |
| `packages/typed_graphql_codegen/lib/src/documents/project_source_map.dart` | Maps offsets of the project text, every file joined by a line break, back to the file they came from | 3 |
| `packages/typed_graphql_codegen/test/documents/project_documents_test.dart` | Tests | 3 |
| `packages/typed_graphql_codegen/test/documents/project_source_map_test.dart` | Tests | 3 |
| `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart` | Generates typed Dart client code from a schema and `.graphql` documents | 5 |
| `packages/typed_graphql_codegen/lib/src/generator/client_project.dart` | A schema and the documents validated against it | 5 |
| `packages/typed_graphql_codegen/lib/src/generator/client_project_loader.dart` | Reads the schema and the documents of a project and validates them with [ClientGenerator.rules] | 5 |
| `packages/typed_graphql_codegen/lib/src/generator/client_project_result.dart` | The outcome of loading a project | 5 |
| `packages/typed_graphql_codegen/lib/src/generator/rules/named_operations_rule.dart` | `GQL503` | 5 |
| `packages/typed_graphql_codegen/lib/src/generator/rules/unsupported_directives_rule.dart` | `GQL504` | 5 |
| `packages/typed_graphql_codegen/lib/src/generator/scalar_mapping_checker.dart` | Checks that each scalar the configuration maps is a custom scalar of the schema (`GQL505`) | 5 |
| `packages/typed_graphql_codegen/test/generator/client_generator_test.dart` | Tests | 5 |
| `packages/typed_graphql_codegen/test/quality/engine_imports_test.dart` | Tests | 5 |
| `packages/typed_graphql_codegen/dartdoc_options.yaml` | Package file | 6 |
| `packages/typed_graphql_codegen/doc/client_codegen.md` | Document | 6 |
| `packages/typed_graphql_codegen/test/doc/category_tags_test.dart` | Tests | 6 |
| `packages/typed_graphql_codegen/test/doc/guide_links_test.dart` | Tests | 6 |
| `packages/typed_graphql_codegen/test/doc/guide_snippets_test.dart` | Tests | 6 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modified | 1, 2, 4, 7 |
| `packages/typed_graphql_codegen/CHANGELOG.md` | Modified | 1, 2, 5, 6, 7 |
| `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart` | Modified | 1, 2, 5 |
| `packages/typed_graphql_codegen/pubspec.yaml` | Modified | 1 |
| `README.md` | Modified | 6 |
| `llms.txt` | Modified | 6 |
| `packages/typed_graphql/CHANGELOG.md` | Modified | 6 |
| `packages/typed_graphql_codegen/README.md` | Modified | 6 |

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

After the last task, also run the M10 packages on every compiler (Chrome only for the core and the client; the codegen package is VM-only):

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 900 dart test --compiler exe test/protocol test/diagnostics)
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 900 dart test --compiler exe)
(cd packages/typed_graphql && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2js test/protocol)
(cd packages/typed_graphql && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2wasm test/protocol)
(cd packages/typed_graphql_client && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2js)
(cd packages/typed_graphql_client && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2wasm)
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 900 dart test --compiler exe)
```

Under `--compiler exe` the codegen tests that start the `dart` tool (the analysis test, the CLI exit-code test) skip themselves with a reason: `Platform.resolvedExecutable` is the compiled test, not `dart`.

---

### Task 1: Read the typed_graphql.yaml configuration

`CodegenConfig.parse` reads `typed_graphql.yaml` into the sealed `ConfigResult` (R7.1, spec section 3): the schema location (a relative path or a URL), the document globs, `schema_types`, `persisted_operations`, scalar mappings (`DartReference`s `<library>#<Name>`) and headers. Every problem is collected in document order: YAML syntax is `GQL500`, a missing, unknown or mistyped key, a malformed path or reference `GQL501`. The two codes come into the core catalog here, with the `yaml` dependency.

Commit on the branch: `52d9793`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/config/codegen_config.dart`, `packages/typed_graphql_codegen/lib/src/config/config_draft.dart`, `packages/typed_graphql_codegen/lib/src/config/config_reader.dart`, `packages/typed_graphql_codegen/lib/src/config/config_report.dart`, `packages/typed_graphql_codegen/lib/src/config/config_result.dart`, `packages/typed_graphql_codegen/lib/src/config/dart_reference.dart`, `packages/typed_graphql_codegen/lib/src/config/dart_reference_reader.dart`, `packages/typed_graphql_codegen/lib/src/config/header_reader.dart`, `packages/typed_graphql_codegen/lib/src/config/relative_path.dart`, `packages/typed_graphql_codegen/lib/src/config/scalar_mapping.dart`, `packages/typed_graphql_codegen/lib/src/config/scalar_mapping_reader.dart`, `packages/typed_graphql_codegen/lib/src/config/schema_location.dart`, `packages/typed_graphql_codegen/lib/src/config/schema_location_reader.dart`
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, `packages/typed_graphql_codegen/pubspec.yaml`
- Test: `packages/typed_graphql_codegen/test/config/codegen_config_test.dart`, `packages/typed_graphql_codegen/test/config/scalar_config_test.dart`

**Interfaces:**
- Consumes: The core: `Source`, `SourceSpan`, `Diagnostic`, `DiagnosticSink`, `DiagnosticCode`; `package:yaml`.
- Produces:
- Diagnostic codes: `GQL500`, `GQL501`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// config/codegen_config.dart
final class CodegenConfig
  const CodegenConfig({
  static ConfigResult parse(String text,
  final SchemaLocation schema
  final List<String> documents
  final String schemaTypes
  final String? persistedOperations
  final Map<String, ScalarMapping> scalars
  final Map<String, String> headers

// config/config_draft.dart
final class ConfigDraft
  SchemaLocation? schema
  String? persistedOperations
  YamlNode? headersKey
  CodegenConfig? build()

// config/config_reader.dart
final class ConfigReader(…)
  ConfigResult read(String text)

// config/config_report.dart
final class ConfigReport(…)
  bool get isClean
  void error(YamlNode node, String message)
  String? string(YamlNode node, String label)
  String? keyText(YamlNode key)

// config/config_result.dart
sealed class const ConfigResult()
final class ConfigSuccess(…)
final class ConfigFailure(…)

// config/dart_reference.dart
final class const DartReference(…)
  int get hashCode
  String toString()

// config/dart_reference_reader.dart
final class const DartReferenceReader()
  DartReference? read(

// config/header_reader.dart
final class const HeaderReader()
  Map<String, String> read(YamlNode node, ConfigReport report)

// config/relative_path.dart
final class const RelativePath()
  String? read(YamlNode node, String label, ConfigReport report)

// config/scalar_mapping.dart
final class const ScalarMapping(…)
  int get hashCode

// config/scalar_mapping_reader.dart
final class const ScalarMappingReader()
  Map<String, ScalarMapping> read(YamlNode node, ConfigReport report)

// config/schema_location.dart
sealed class const SchemaLocation()
final class const SchemaFile(…)
  bool get isIntrospection
  int get hashCode
final class SchemaUrl(…)
  int get hashCode

// config/schema_location_reader.dart
final class const SchemaLocationReader()
  SchemaLocation? read(YamlNode node, ConfigReport report)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/config/codegen_config_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _path = 'typed_graphql.yaml';

void main() {
  CodegenConfig read(String text) {
    final result = CodegenConfig.parse(text, path: _path);
    if (result is! ConfigSuccess) fail('expected success, got $result');
    return result.config;
  }

  List<String> problems(String text) {
    final result = CodegenConfig.parse(text, path: _path);
    if (result is! ConfigFailure) fail('expected failure, got $result');
    return [for (final diagnostic in result.diagnostics) '$diagnostic'];
  }

  group('valid files', () {
    test('a full file is read with every key', () {
      final config = read(r'''
schema: https://api.example.com/graphql
documents:
  - lib/**.graphql
  - test/**.graphql
schema_types: lib/src/schema.dart
persisted_operations: lib/operations.json
scalars:
  Url:
    type: Uri
    codec: package:my_app/codecs.dart#UrlCodec
  DateTime:
    type: dart:core#DateTime
    codec: package:my_app/codecs.dart#DateTimeCodec
  Money:
    type: package:money/money.dart#Money
    codec: package:my_app/codecs.dart#MoneyCodec
headers:
  X-Trace: abc
  Authorization: Bearer ${TOKEN}
''');
      expect(
        config.schema,
        SchemaUrl(Uri.parse('https://api.example.com/graphql')),
      );
      expect(config.documents, ['lib/**.graphql', 'test/**.graphql']);
      expect(config.schemaTypes, 'lib/src/schema.dart');
      expect(config.persistedOperations, 'lib/operations.json');
      expect(config.scalars.keys, ['DateTime', 'Money', 'Url']);
      expect(config.headers, {
        'Authorization': r'Bearer ${TOKEN}',
        'X-Trace': 'abc',
      });
    });

    test('a file with only a schema takes the defaults', () {
      final config = read('schema: schema.graphql\n');
      expect(config.schema, const SchemaFile('schema.graphql'));
      expect(config.documents, ['lib/**.graphql']);
      expect(config.schemaTypes, 'lib/schema.graphql.dart');
      expect(config.persistedOperations, isNull);
      expect(config.scalars, isEmpty);
      expect(config.headers, isEmpty);
    });

    test('a JSON schema file is an introspection result', () {
      final config = read('schema: introspection.json\n');
      expect(config.schema, const SchemaFile('introspection.json'));
      expect((config.schema as SchemaFile).isIntrospection, isTrue);
    });

    test('documents may be a single string', () {
      expect(read('schema: s.graphql\ndocuments: ops/*.graphql\n').documents, [
        'ops/*.graphql',
      ]);
    });

    test('dart:core#DateTime has no library', () {
      final config = read('''
schema: s.graphql
scalars:
  Moment:
    type: dart:core#DateTime
    codec: package:a/a.dart#C
''');
      expect(
        config.scalars['Moment']?.type,
        const DartReference(null, 'DateTime'),
      );
    });

    test('a bare core type has no library', () {
      final config = read('''
schema: s.graphql
scalars:
  Moment:
    type: DateTime
    codec: package:a/a.dart#C
''');
      expect(
        config.scalars['Moment'],
        const ScalarMapping(
          DartReference(null, 'DateTime'),
          DartReference('package:a/a.dart', 'C'),
        ),
      );
    });

    test('the maps are unmodifiable', () {
      final config = read('schema: https://h.dev/g\nheaders:\n  A: b\n');
      expect(() => config.headers['C'] = 'd', throwsUnsupportedError);
    });

    test('a URL schema keeps its headers raw', () {
      final config = read(
        'schema: http://localhost:4000/graphql\nheaders:\n'
        r'  Authorization: ${T}'
        '\n',
      );
      expect(config.headers, {'Authorization': r'${T}'});
    });
  });

  group('syntax errors', () {
    test('invalid YAML is a GQL500 at its place', () {
      expect(problems('schema: [a\n'), hasLength(1));
      expect(problems('schema: [a\n').single, startsWith('$_path:'));
      expect(problems('schema: [a\n').single, contains('error GQL500: '));
    });

    test('a duplicate key is a GQL500', () {
      expect(
        problems('schema: a.graphql\nschema: b.graphql\n').single,
        contains('error GQL500: '),
      );
    });
  });

  group('structure problems', () {
    test('an empty file must be a map', () {
      expect(problems(''), [
        '$_path:1:1: error GQL501: The configuration must be a YAML map.',
      ]);
    });

    test('a list root must be a map', () {
      expect(problems('- a\n'), [
        '$_path:1:1: error GQL501: The configuration must be a YAML map.',
      ]);
    });

    test('the schema key is required', () {
      expect(problems('documents: a.graphql\n'), [
        "$_path:1:1: error GQL501: The key 'schema' is required.",
      ]);
    });

    test('an unknown key lists the known ones', () {
      expect(problems('schema: s.graphql\nschemas: x\n'), [
        "$_path:2:1: error GQL501: Unknown key 'schemas'; the keys are "
            "'documents', 'headers', 'persisted_operations', 'scalars', "
            "'schema', 'schema_types'.",
      ]);
    });

    test('a value of the wrong kind says what is expected', () {
      expect(problems('schema: s.graphql\nschema_types: 5\n'), [
        "$_path:2:15: error GQL501: 'schema_types' must be a string.",
      ]);
    });

    test('a null schema is not a string', () {
      expect(problems('schema:\n'), [
        "$_path:1:7: error GQL501: 'schema' must be a string.",
      ]);
    });
  });

  group('path problems', () {
    test('an empty path', () {
      expect(problems('schema: ""\n'), [
        "$_path:1:9: error GQL501: 'schema' must not be empty.",
      ]);
    });

    test('an absolute path', () {
      expect(problems('schema: /etc/s.graphql\n'), [
        "$_path:1:9: error GQL501: 'schema' must be a relative path.",
      ]);
    });

    test('a drive letter path', () {
      expect(problems('schema: C:/s.graphql\n'), [
        "$_path:1:9: error GQL501: 'schema' must be a relative path.",
      ]);
    });

    test('a backslash', () {
      expect(problems("schema: 'a\\b.graphql'\n"), [
        "$_path:1:9: error GQL501: 'schema' must use '/' as the separator.",
      ]);
    });

    test('a parent segment', () {
      expect(problems('schema: ../s.graphql\n'), [
        "$_path:1:9: error GQL501: 'schema' must not have a '..' segment.",
      ]);
    });

    test('schema_types must end with .dart', () {
      expect(problems('schema: s.graphql\nschema_types: lib/s.txt\n'), [
        "$_path:2:15: error GQL501: 'schema_types' must end with '.dart'.",
      ]);
    });

    test('persisted_operations must end with .json', () {
      expect(problems('schema: s.graphql\npersisted_operations: p.txt\n'), [
        "$_path:2:23: error GQL501: 'persisted_operations' must end with "
            "'.json'.",
      ]);
    });

    test('an empty documents list', () {
      expect(problems('schema: s.graphql\ndocuments: []\n'), [
        "$_path:2:12: error GQL501: 'documents' must not be an empty list.",
      ]);
    });

    test('a bad entry of documents', () {
      expect(problems('schema: s.graphql\ndocuments:\n  - /abs\n'), [
        "$_path:3:5: error GQL501: 'documents' must be a relative path.",
      ]);
    });
  });

  group('schema location problems', () {
    test('a URL without a host', () {
      expect(problems('schema: http://\n'), [
        "$_path:1:9: error GQL501: 'schema' is not a valid URL.",
      ]);
    });

    test('headers need a schema URL', () {
      expect(problems('schema: s.graphql\nheaders:\n  A: b\n'), [
        "$_path:2:1: error GQL501: 'headers' apply only to a schema URL.",
      ]);
    });
  });

  group('headers problems', () {
    test('a header name with a colon', () {
      expect(problems('schema: https://h.dev/g\nheaders:\n  "A:b": c\n'), [
        "$_path:3:3: error GQL501: 'A:b' is not a valid header name.",
      ]);
    });

    test('a header value that is not a string', () {
      expect(problems('schema: https://h.dev/g\nheaders:\n  A: 1\n'), [
        "$_path:3:6: error GQL501: 'headers.A' must be a string.",
      ]);
    });

    test('headers that are not a map', () {
      expect(problems('schema: https://h.dev/g\nheaders: x\n'), [
        "$_path:2:10: error GQL501: 'headers' must be a map of header names "
            'to strings.',
      ]);
    });
  });
}
```

Create `packages/typed_graphql_codegen/test/config/scalar_config_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _path = 'typed_graphql.yaml';
const _codec = '    codec: package:a/a.dart#C\n';

void main() {
  List<String> problems(String text) {
    final result = CodegenConfig.parse(text, path: _path);
    if (result is! ConfigFailure) fail('expected failure, got $result');
    return [for (final diagnostic in result.diagnostics) '$diagnostic'];
  }

  String scalar(String body) => 'schema: s.graphql\nscalars:\n  Moment:\n$body';

  group('scalars', () {
    test('a scalar name must be a GraphQL name', () {
      expect(problems('schema: s.graphql\nscalars:\n  1Bad: {}\n'), [
        '$_path:3:3: error GQL501: A scalar name must be a GraphQL name.',
      ]);
    });

    test('a scalar must be a map', () {
      expect(problems('schema: s.graphql\nscalars:\n  Moment: x\n'), [
        "$_path:3:11: error GQL501: Scalar 'Moment' must be a map with "
            "'type' and 'codec'.",
      ]);
    });

    test('scalars must be a map', () {
      expect(problems('schema: s.graphql\nscalars: x\n'), [
        "$_path:2:10: error GQL501: 'scalars' must be a map of scalar names.",
      ]);
    });

    test('a missing codec is reported at the scalar', () {
      expect(problems(scalar('    type: Uri\n')), [
        "$_path:4:5: error GQL501: Scalar 'Moment' needs a 'codec'.",
      ]);
    });

    test('a missing type is reported at the scalar', () {
      expect(problems(scalar(_codec)), [
        "$_path:4:5: error GQL501: Scalar 'Moment' needs a 'type'.",
      ]);
    });

    test('an unknown scalar key', () {
      expect(problems(scalar('    type: Uri\n$_codec    extra: 1\n')), [
        "$_path:6:5: error GQL501: Scalar 'Moment' has the unknown key "
            "'extra'; the keys are 'codec' and 'type'.",
      ]);
    });

    test('a bare name outside dart:core needs a library', () {
      expect(problems(scalar('    type: Money\n$_codec')), [
        "$_path:4:11: error GQL501: 'type' names 'Money' without a "
            "library; write 'package:...#Money'.",
      ]);
    });

    test('a bare codec is rejected', () {
      expect(problems(scalar('    type: Uri\n    codec: UrlCodec\n')), [
        "$_path:5:12: error GQL501: 'codec' names 'UrlCodec' without a "
            "library; write 'package:...#UrlCodec'.",
      ]);
    });

    test('a codec in dart:core has no library', () {
      expect(problems(scalar('    type: Uri\n    codec: dart:core#Codec\n')), [
        "$_path:5:12: error GQL501: 'codec' must name a library.",
      ]);
    });

    test('a library that is not a package or dart: library', () {
      expect(problems(scalar('    type: x/y.dart#T\n$_codec')), [
        "$_path:4:11: error GQL501: 'type' must be '<library>#<Name>', "
            "such as 'package:my_app/codecs.dart#MyType'.",
      ]);
    });

    test('a private name', () {
      expect(
        problems(scalar('    type: Uri\n    codec: package:a/a.dart#_Codec\n')),
        [
          "$_path:5:12: error GQL501: 'codec' must be '<library>#<Name>', "
              "such as 'package:my_app/codecs.dart#MyType'.",
        ],
      );
    });

    test('a type that is not a string', () {
      expect(problems(scalar('    type: 5\n$_codec')), [
        "$_path:4:11: error GQL501: 'type' must be a string.",
      ]);
    });
  });

  group('several problems', () {
    test('are reported together in document order', () {
      expect(
        problems(
          'schema: /abs\n'
          'bogus: 1\n'
          'schema_types: x.txt\n'
          'documents: []\n',
        ),
        [
          "$_path:1:9: error GQL501: 'schema' must be a relative path.",
          "$_path:2:1: error GQL501: Unknown key 'bogus'; the keys are "
              "'documents', 'headers', 'persisted_operations', 'scalars', "
              "'schema', 'schema_types'.",
          "$_path:3:15: error GQL501: 'schema_types' must end with '.dart'.",
          "$_path:4:12: error GQL501: 'documents' must not be an empty list.",
        ],
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/config/codegen_config_test.dart test/config/scalar_config_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Update the package files**

In `packages/typed_graphql_codegen/pubspec.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,6 +11,7 @@ environment:
 
 dependencies:
   typed_graphql: ^0.0.1
+  yaml: ^3.1.3
 
 dev_dependencies:
   test: ^1.31.0
```

- [ ] **Step 4: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -510,4 +510,12 @@ enum DiagnosticCode(
   /// `GQL238`: an operation whose field cost or type cost is more than the
   /// maximum `MaxCostRule` allows.
   maxCostExceeded('GQL238'),
+
+  /// `GQL500`: a `typed_graphql.yaml` that is not valid YAML; the message is
+  /// the YAML parser's.
+  configSyntax('GQL500'),
+
+  /// `GQL501`: a missing, unknown or mistyped key, or a malformed path or Dart
+  /// reference, in the code generator's configuration.
+  invalidConfig('GQL501'),
 }
```

Create `packages/typed_graphql_codegen/lib/src/config/codegen_config.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'config_reader.dart';
import 'config_result.dart';
import 'scalar_mapping.dart';
import 'schema_location.dart';

/// The settings of `typed_graphql.yaml` (R7.1), read by [parse].
///
/// {@category codegen}
final class CodegenConfig {
  /// Creates a configuration; every argument but [schema] has the default the
  /// file's missing key has.
  const CodegenConfig({
    required this.schema,
    this.documents = const ['lib/**.graphql'],
    this.schemaTypes = 'lib/schema.graphql.dart',
    this.persistedOperations,
    this.scalars = const {},
    this.headers = const {},
  });

  /// Reads the text of the configuration file at [path].
  ///
  /// Bad input never throws: a YAML syntax error is one `GQL500`, every other
  /// problem a `GQL501`, all in a [ConfigFailure]. [path] only names the file
  /// in the diagnostics.
  static ConfigResult parse(String text, {required String path}) =>
      ConfigReader(Source(text, name: path)).read(text);

  /// Where the schema is: a file or an endpoint.
  final SchemaLocation schema;

  /// The globs, relative to the configuration file, of the `.graphql`
  /// operation documents.
  final List<String> documents;

  /// The path of the generated schema types file, ending with `.dart`.
  final String schemaTypes;

  /// The path of the persisted operations manifest, ending with `.json`; null
  /// when none is written.
  final String? persistedOperations;

  /// The custom scalar mappings by scalar name, sorted by name.
  final Map<String, ScalarMapping> scalars;

  /// The HTTP headers of the introspection request by name, sorted by name;
  /// values are raw, `${NAME}` is not expanded.
  final Map<String, String> headers;
}
```

Create `packages/typed_graphql_codegen/lib/src/config/config_draft.dart`:

```dart
import 'package:yaml/yaml.dart';

import 'codegen_config.dart';
import 'scalar_mapping.dart';
import 'schema_location.dart';

/// The values read so far from a configuration, with the defaults of the keys
/// not met yet.
final class ConfigDraft {
  /// The location of the schema; null until a valid `schema` is read.
  SchemaLocation? schema;

  /// The `documents` globs.
  List<String> documents = const ['lib/**.graphql'];

  /// The `schema_types` path.
  String schemaTypes = 'lib/schema.graphql.dart';

  /// The `persisted_operations` path, if any.
  String? persistedOperations;

  /// The `scalars` mappings.
  Map<String, ScalarMapping> scalars = const {};

  /// The `headers`.
  Map<String, String> headers = const {};

  /// The `headers` key, when the file has one.
  YamlNode? headersKey;

  /// The configuration, or null when [schema] was not read.
  CodegenConfig? build() {
    final location = schema;
    if (location == null) return null;
    return CodegenConfig(
      schema: location,
      documents: List.unmodifiable(documents),
      schemaTypes: schemaTypes,
      persistedOperations: persistedOperations,
      scalars: Map.unmodifiable(scalars),
      headers: Map.unmodifiable(headers),
    );
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/config/config_reader.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:yaml/yaml.dart';

import 'codegen_config.dart';
import 'config_draft.dart';
import 'config_report.dart';
import 'config_result.dart';
import 'header_reader.dart';
import 'relative_path.dart';
import 'scalar_mapping_reader.dart';
import 'schema_location.dart';
import 'schema_location_reader.dart';

/// Turns the text of `typed_graphql.yaml` into a [ConfigResult].
final class ConfigReader(
  /// The configuration file's text and name.
  final Source source,
) {
  /// Creates a reader of [source].
  this;

  static const List<String> _keys = [
    'documents',
    'headers',
    'persisted_operations',
    'scalars',
    'schema',
    'schema_types',
  ];

  /// Reads [text], the body of [source].
  ConfigResult read(String text) {
    final YamlNode root;
    try {
      root = loadYamlNode(text);
    } on YamlException catch (error) {
      final start = error.span?.start.offset ?? 0;
      final end = error.span?.end.offset ?? 0;
      return ConfigFailure([
        Diagnostic(
          .configSyntax,
          .error,
          error.message,
          span: SourceSpan(source, start, end),
        ),
      ]);
    }
    final report = ConfigReport(source);
    final config = _readRoot(root, report);
    if (config == null || !report.isClean) {
      return ConfigFailure(report.diagnostics);
    }
    return ConfigSuccess(config);
  }

  CodegenConfig? _readRoot(YamlNode root, ConfigReport report) {
    if (root is! YamlMap) {
      report.error(root, 'The configuration must be a YAML map.');
      return null;
    }
    final draft = ConfigDraft();
    for (final MapEntry(:key, :value) in root.nodes.entries) {
      if (key is YamlNode) _readEntry(draft, key, value, report);
    }
    final headersKey = draft.headersKey;
    if (draft.schema is SchemaFile && headersKey != null) {
      report.error(headersKey, "'headers' apply only to a schema URL.");
    }
    if (!root.containsKey('schema')) {
      report.error(root, "The key 'schema' is required.");
    }
    return draft.build();
  }

  void _readEntry(
    ConfigDraft draft,
    YamlNode key,
    YamlNode value,
    ConfigReport report,
  ) {
    switch (report.keyText(key)) {
      case 'schema':
        draft.schema = const SchemaLocationReader().read(value, report);
      case 'documents':
        draft.documents = _readDocuments(value, report) ?? draft.documents;
      case 'schema_types':
        draft.schemaTypes =
            _readSuffixed(value, 'schema_types', '.dart', report) ??
            draft.schemaTypes;
      case 'persisted_operations':
        draft.persistedOperations = _readSuffixed(
          value,
          'persisted_operations',
          '.json',
          report,
        );
      case 'scalars':
        draft.scalars = const ScalarMappingReader().read(value, report);
      case 'headers':
        draft.headersKey = key;
        draft.headers = const HeaderReader().read(value, report);
      default:
        report.error(
          key,
          "Unknown key '${key.span.text}'; the keys are "
          "${_keys.map((name) => "'$name'").join(', ')}.",
        );
    }
  }

  List<String>? _readDocuments(YamlNode node, ConfigReport report) {
    if (node is! YamlList) {
      final path = const RelativePath().read(node, 'documents', report);
      return path == null ? null : [path];
    }
    if (node.nodes.isEmpty) {
      report.error(node, "'documents' must not be an empty list.");
      return null;
    }
    final paths = <String>[];
    for (final item in node.nodes) {
      final path = const RelativePath().read(item, 'documents', report);
      if (path != null) paths.add(path);
    }
    return paths;
  }

  String? _readSuffixed(
    YamlNode node,
    String label,
    String suffix,
    ConfigReport report,
  ) {
    final path = const RelativePath().read(node, label, report);
    if (path == null) return null;
    if (path.endsWith(suffix)) return path;
    report.error(node, "'$label' must end with '$suffix'.");
    return null;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/config/config_report.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:yaml/yaml.dart';

/// Collects the `GQL501` problems of one configuration read, in the order the
/// reader meets the nodes.
final class ConfigReport(
  /// The text of the configuration file.
  final Source source,
) {
  /// Creates an empty report over [source].
  this;

  /// The problems reported so far.
  final List<Diagnostic> diagnostics = [];

  /// Whether no problem was reported.
  bool get isClean => diagnostics.isEmpty;

  /// Reports [message] at [node].
  void error(YamlNode node, String message) {
    diagnostics.add(
      Diagnostic(
        .invalidConfig,
        .error,
        message,
        span: SourceSpan(source, node.span.start.offset, node.span.end.offset),
      ),
    );
  }

  /// Returns the string [node] holds, or reports that [label] must be a
  /// string and returns null.
  String? string(YamlNode node, String label) {
    if (node case YamlScalar(value: final String value)) return value;
    error(node, "'$label' must be a string.");
    return null;
  }

  /// Returns the text of a map key, or null when it is not a string.
  String? keyText(YamlNode key) {
    if (key case YamlScalar(value: final String value)) return value;
    return null;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/config/config_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'codegen_config.dart';

/// The outcome of [CodegenConfig.parse]: a configuration or the problems that
/// stop one.
///
/// {@category codegen}
sealed class const ConfigResult() {
  /// Creates a result.
  this;
}

/// A configuration that was read without errors.
///
/// {@category codegen}
final class ConfigSuccess(
  /// The configuration.
  final CodegenConfig config,
) extends ConfigResult {
  /// Creates a success holding [config].
  this;
}

/// A configuration that has errors.
///
/// {@category codegen}
final class ConfigFailure(
  List<Diagnostic> diagnostics,
) extends ConfigResult {
  /// Creates a failure with [diagnostics].
  this;

  /// The problems, in document order; never empty.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
```

Create `packages/typed_graphql_codegen/lib/src/config/dart_reference.dart`:

```dart
/// A Dart declaration the configuration names, such as the type or the codec
/// of a scalar: `package:my_app/codecs.dart#DateTimeCodec`, or the bare name
/// of a `dart:core` type such as `DateTime`.
///
/// {@category codegen}
final class const DartReference(
  /// The library that declares [name], such as
  /// `package:my_app/codecs.dart`; null for a `dart:core` type.
  final String? library,

  /// The declaration's name.
  final String name,
) {
  /// Creates a reference to [name] in [library].
  this;

  @override
  bool operator ==(Object other) =>
      other is DartReference && other.library == library && other.name == name;

  @override
  int get hashCode => Object.hash(library, name);

  @override
  String toString() => switch (library) {
    final library? => '$library#$name',
    null => name,
  };
}
```

Create `packages/typed_graphql_codegen/lib/src/config/dart_reference_reader.dart`:

```dart
import 'package:yaml/yaml.dart';

import 'config_report.dart';
import 'dart_reference.dart';

/// Reads a [DartReference] written as `<library>#<Name>` or, for a `dart:core`
/// type, as its bare name.
final class const DartReferenceReader() {
  /// Creates the reader.
  this;

  static final RegExp _library = RegExp(
    r'^(package:[^#\s]+\.dart|dart:[a-z_]+)$',
  );
  static final RegExp _identifier = RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$');
  static const Set<String> _coreTypes = {
    'BigInt',
    'bool',
    'DateTime',
    'double',
    'Duration',
    'int',
    'num',
    'Object',
    'String',
    'Uri',
  };

  /// Returns the reference [node] holds under [label], or reports the problem
  /// and returns null. A reference without a library is accepted only when
  /// [isBareCoreAllowed] and it names a `dart:core` type.
  DartReference? read(
    YamlNode node,
    String label,
    ConfigReport report, {
    required bool isBareCoreAllowed,
  }) {
    final text = report.string(node, label);
    if (text == null) return null;
    final hash = text.indexOf('#');
    if (hash < 0) {
      return _readBare(node, label, text, report, isBareCoreAllowed);
    }
    final library = text.substring(0, hash);
    final name = text.substring(hash + 1);
    if (!_library.hasMatch(library) || !_identifier.hasMatch(name)) {
      report.error(
        node,
        "'$label' must be '<library>#<Name>', such as "
        "'package:my_app/codecs.dart#MyType'.",
      );
      return null;
    }
    return DartReference(library == 'dart:core' ? null : library, name);
  }

  DartReference? _readBare(
    YamlNode node,
    String label,
    String text,
    ConfigReport report,
    bool isBareCoreAllowed,
  ) {
    if (isBareCoreAllowed && _coreTypes.contains(text)) {
      return DartReference(null, text);
    }
    report.error(
      node,
      "'$label' names '$text' without a library; write "
      "'package:...#$text'.",
    );
    return null;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/config/header_reader.dart`:

```dart
import 'package:yaml/yaml.dart';

import 'config_report.dart';

/// Reads the `headers` map: header names to raw string values.
final class const HeaderReader() {
  /// Creates the reader.
  this;

  static final RegExp _name = RegExp(r'^[^\s:]+$');

  /// Returns the headers of [node], sorted by name; the entries with problems
  /// are left out and reported.
  Map<String, String> read(YamlNode node, ConfigReport report) {
    if (node is! YamlMap) {
      report.error(node, "'headers' must be a map of header names to strings.");
      return const {};
    }
    final headers = <String, String>{};
    for (final MapEntry(:key, :value) in node.nodes.entries) {
      if (key is! YamlNode) continue;
      final name = report.string(key, 'headers');
      if (name == null) continue;
      if (!_name.hasMatch(name)) {
        report.error(key, "'$name' is not a valid header name.");
        continue;
      }
      final text = report.string(value, 'headers.$name');
      if (text != null) headers[name] = text;
    }
    return {
      for (final name in headers.keys.toList()..sort()) name: headers[name]!,
    };
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/config/relative_path.dart`:

```dart
import 'package:yaml/yaml.dart';

import 'config_report.dart';

/// Reads a path of the configuration: relative to the configuration file,
/// with `/` separators, and inside its folder.
final class const RelativePath() {
  /// Creates the reader.
  this;

  static final RegExp _driveLetter = RegExp('^[A-Za-z]:');

  /// Returns the path [node] holds, or reports why it is not one named by
  /// [label] and returns null.
  String? read(YamlNode node, String label, ConfigReport report) {
    final path = report.string(node, label);
    if (path == null) return null;
    final problem = _problemOf(path);
    if (problem == null) return path;
    report.error(node, "'$label' $problem");
    return null;
  }

  String? _problemOf(String path) {
    if (path.isEmpty) return 'must not be empty.';
    if (path.contains(r'\')) return "must use '/' as the separator.";
    if (path.startsWith('/') || _driveLetter.hasMatch(path)) {
      return 'must be a relative path.';
    }
    if (path.split('/').contains('..')) {
      return "must not have a '..' segment.";
    }
    return null;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/config/scalar_mapping.dart`:

```dart
import 'dart_reference.dart';

/// How generated code holds a custom scalar (R7.8): its Dart [type] and the
/// [codec] that reads and writes it, a class with a const constructor that
/// implements `ScalarCodec<type>`.
///
/// {@category codegen}
final class const ScalarMapping(
  /// The Dart type of the scalar's values.
  final DartReference type,

  /// The codec class, constructed as `const Codec()` in generated code.
  final DartReference codec,
) {
  /// Creates a mapping to [type] through [codec].
  this;

  @override
  bool operator ==(Object other) =>
      other is ScalarMapping && other.type == type && other.codec == codec;

  @override
  int get hashCode => Object.hash(type, codec);
}
```

Create `packages/typed_graphql_codegen/lib/src/config/scalar_mapping_reader.dart`:

```dart
import 'package:yaml/yaml.dart';

import 'config_report.dart';
import 'dart_reference.dart';
import 'dart_reference_reader.dart';
import 'scalar_mapping.dart';

/// Reads the `scalars` map: scalar names to their Dart type and codec.
final class const ScalarMappingReader() {
  /// Creates the reader.
  this;

  static final RegExp _name = RegExp(r'^[_A-Za-z][_0-9A-Za-z]*$');

  /// Returns the mappings of [node], sorted by scalar name; the entries with
  /// problems are left out and reported.
  Map<String, ScalarMapping> read(YamlNode node, ConfigReport report) {
    if (node is! YamlMap) {
      report.error(node, "'scalars' must be a map of scalar names.");
      return const {};
    }
    final mappings = <String, ScalarMapping>{};
    for (final MapEntry(:key, :value) in node.nodes.entries) {
      if (key is! YamlNode) continue;
      final text = report.keyText(key);
      if (text == null || !_name.hasMatch(text)) {
        report.error(key, 'A scalar name must be a GraphQL name.');
        continue;
      }
      final mapping = _readMapping(text, value, report);
      if (mapping != null) mappings[text] = mapping;
    }
    return {
      for (final name in mappings.keys.toList()..sort()) name: mappings[name]!,
    };
  }

  ScalarMapping? _readMapping(String name, YamlNode node, ConfigReport report) {
    if (node is! YamlMap) {
      report.error(
        node,
        "Scalar '$name' must be a map with 'type' and 'codec'.",
      );
      return null;
    }
    DartReference? type;
    DartReference? codec;
    var isValid = true;
    for (final MapEntry(:key, :value) in node.nodes.entries) {
      if (key is! YamlNode) continue;
      switch (report.keyText(key)) {
        case 'type':
          type = const DartReferenceReader().read(
            value,
            'type',
            report,
            isBareCoreAllowed: true,
          );
          isValid = isValid && type != null;
        case 'codec':
          codec = _readCodec(value, report);
          isValid = isValid && codec != null;
        default:
          report.error(
            key,
            "Scalar '$name' has the unknown key '${key.span.text}'; the keys "
            "are 'codec' and 'type'.",
          );
          isValid = false;
      }
    }
    isValid = _hasRequiredKeys(name, node, report) && isValid;
    if (isValid && type != null && codec != null) {
      return ScalarMapping(type, codec);
    }
    return null;
  }

  bool _hasRequiredKeys(String name, YamlMap node, ConfigReport report) {
    var hasAll = true;
    for (final key in ['type', 'codec']) {
      if (!node.containsKey(key)) {
        report.error(node, "Scalar '$name' needs a '$key'.");
        hasAll = false;
      }
    }
    return hasAll;
  }

  DartReference? _readCodec(YamlNode value, ConfigReport report) {
    final codec = const DartReferenceReader().read(
      value,
      'codec',
      report,
      isBareCoreAllowed: false,
    );
    if (codec != null && codec.library == null) {
      report.error(value, "'codec' must name a library.");
      return null;
    }
    return codec;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/config/schema_location.dart`:

```dart
/// Where the generator finds the schema (R7.1): a file in the project or an
/// introspection URL.
///
/// {@category codegen}
sealed class const SchemaLocation() {
  /// Creates a location.
  this;
}

/// A schema file: SDL, or an introspection result when the path ends with
/// `.json`.
///
/// {@category codegen}
final class const SchemaFile(
  /// The path from the configuration file's folder, with `/` separators.
  final String path,
) extends SchemaLocation {
  /// Creates the location of the file at [path].
  this;

  /// Whether the file holds an introspection result rather than SDL.
  bool get isIntrospection => path.endsWith('.json');

  @override
  bool operator ==(Object other) => other is SchemaFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// A GraphQL endpoint the CLI asks for its schema with the introspection
/// query.
///
/// {@category codegen}
final class SchemaUrl(
  /// The endpoint, `http` or `https`.
  final Uri url,
) extends SchemaLocation {
  /// Creates the location of the endpoint at [url].
  this;

  @override
  bool operator ==(Object other) => other is SchemaUrl && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
```

Create `packages/typed_graphql_codegen/lib/src/config/schema_location_reader.dart`:

```dart
import 'package:yaml/yaml.dart';

import 'config_report.dart';
import 'relative_path.dart';
import 'schema_location.dart';

/// Reads the `schema` value: an `http` or `https` URL, or a relative path.
final class const SchemaLocationReader() {
  /// Creates the reader.
  this;

  /// Returns the location [node] holds, or reports the problem and returns
  /// null.
  SchemaLocation? read(YamlNode node, ConfigReport report) {
    final text = report.string(node, 'schema');
    if (text == null) return null;
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      final path = const RelativePath().read(node, 'schema', report);
      return path == null ? null : SchemaFile(path);
    }
    final url = Uri.tryParse(text);
    if (url == null || url.host.isEmpty) {
      report.error(node, "'schema' is not a valid URL.");
      return null;
    }
    return SchemaUrl(url);
  }
}
```

In `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,12 @@
 /// The typed_graphql code generator and its CLI: Dart client code from .graphql
 /// operations and SDL-first server code, without the analyzer.
 ///
-/// Under construction: nothing is exported yet; see the package README.
+/// Under construction: so far the package reads `typed_graphql.yaml`
+/// ([CodegenConfig]); see the package README.
 library;
+
+export 'src/config/codegen_config.dart';
+export 'src/config/config_result.dart';
+export 'src/config/dart_reference.dart';
+export 'src/config/scalar_mapping.dart';
+export 'src/config/schema_location.dart';
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/config/codegen_config_test.dart test/config/scalar_config_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- `CodegenConfig.parse` reads `typed_graphql.yaml` (R7.1) into a
  `ConfigResult`; its problems are `GQL500` (YAML syntax) and `GQL501`.
```

- [ ] **Step 7: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/lib/src/config/codegen_config.dart packages/typed_graphql_codegen/lib/src/config/config_draft.dart packages/typed_graphql_codegen/lib/src/config/config_reader.dart packages/typed_graphql_codegen/lib/src/config/config_report.dart packages/typed_graphql_codegen/lib/src/config/config_result.dart packages/typed_graphql_codegen/lib/src/config/dart_reference.dart packages/typed_graphql_codegen/lib/src/config/dart_reference_reader.dart packages/typed_graphql_codegen/lib/src/config/header_reader.dart packages/typed_graphql_codegen/lib/src/config/relative_path.dart packages/typed_graphql_codegen/lib/src/config/scalar_mapping.dart packages/typed_graphql_codegen/lib/src/config/scalar_mapping_reader.dart packages/typed_graphql_codegen/lib/src/config/schema_location.dart packages/typed_graphql_codegen/lib/src/config/schema_location_reader.dart packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart packages/typed_graphql_codegen/pubspec.yaml packages/typed_graphql_codegen/test/config/codegen_config_test.dart packages/typed_graphql_codegen/test/config/scalar_config_test.dart
git commit -q -m "feat(typed_graphql_codegen): read the typed_graphql.yaml configuration" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Load the schema from SDL or an introspection result

`SchemaLoader` builds a `ValidSchema` from a `ProjectFile` (spec section 4): SDL through the core parser (without the operation token limit) and `SchemaBuilder.fromSdl` with the file's `Source`, or, for a `.json` path, an introspection result (also a response with `data`) through `IntrospectionFileReader` and `SchemaBuilder.fromIntrospection`; then `SchemaValidator`. A file that is not JSON or not a JSON object is the new `GQL502`; every other problem keeps its core code.

Commit on the branch: `2a3fd55`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/project/project_file.dart`, `packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart`, `packages/typed_graphql_codegen/lib/src/schema/schema_load_result.dart`, `packages/typed_graphql_codegen/lib/src/schema/schema_loader.dart`
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`
- Test: `packages/typed_graphql_codegen/test/schema/schema_loader_test.dart`

**Interfaces:**
- Consumes: Task 1 (`SchemaLocation`); the core `Parser`, `SchemaBuilder`, `SchemaValidator`, `JsonReader`.
- Produces:
- Diagnostic codes: `GQL502`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// project/project_file.dart
final class const ProjectFile(…)
  int get hashCode
  String toString()

// schema/introspection_file_reader.dart
final class const IntrospectionFileReader()
  BuildResult read(String text, Source source)

// schema/schema_load_result.dart
sealed class const SchemaLoadResult()
final class SchemaLoaded(…)
final class SchemaNotLoaded(…)

// schema/schema_loader.dart
final class const SchemaLoader()
  SchemaLoadResult load(ProjectFile file)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/schema/schema_loader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _sdl = 'type Query { hello: String }\n';

void main() {
  const loader = SchemaLoader();

  SchemaLoadResult load(String path, String text) =>
      loader.load(ProjectFile(path, text));

  List<String> problems(String path, String text) {
    final result = load(path, text);
    if (result is! SchemaNotLoaded) fail('expected failure, got $result');
    return [for (final diagnostic in result.diagnostics) '$diagnostic'];
  }

  ValidSchema loaded(String path, String text) {
    final result = load(path, text);
    if (result is! SchemaLoaded) fail('expected a schema, got $result');
    return result.schema;
  }

  String introspectionOf(String sdl) {
    final document = const Parser().parse(Source(sdl)).requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    return schema.toIntrospection().toString();
  }

  group('SDL', () {
    test('a valid schema loads', () {
      final schema = loaded('schema.graphql', _sdl).schema;
      expect(schema.typeNamed('Query'), isA<ObjectType>());
    });

    test('a syntax error is printed at its place', () {
      expect(problems('schema.graphql', 'type Query {\n  hello String\n}\n'), [
        'schema.graphql:2:9: error GQL007: Expected ":", found Name "String".',
      ]);
    });

    test('a build error is reported', () {
      expect(problems('schema.graphql', '$_sdl\ntype Query { b: Int }\n'), [
        'schema.graphql:3:6: error GQL101: There can be only one type named '
            '"Query".',
      ]);
    });

    test('a validation error is reported', () {
      expect(problems('schema.graphql', 'type Query\n'), [
        'schema.graphql:1:1: error GQL125: Type Query must define one or '
            'more fields.',
      ]);
    });

    test('a schema of more than 15000 tokens loads', () {
      final fields = [for (var i = 0; i < 4000; i++) '  f$i: Int'];
      final text = 'type Query {\n${fields.join('\n')}\n}\n';
      expect(
        loaded('schema.graphql', text).schema.typeNamed('Query'),
        isNotNull,
      );
    });
  });

  group('introspection', () {
    test('a result loads', () {
      final text = introspectionOf(_sdl);
      expect(loaded('x.json', text).schema.typeNamed('Query'), isNotNull);
    });

    test('a response with data loads', () {
      final text = '{"data": ${introspectionOf(_sdl)}}';
      expect(loaded('x.json', text).schema.typeNamed('Query'), isNotNull);
    });

    test('text that is not JSON is reported', () {
      final messages = problems('x.json', '{');
      expect(messages, hasLength(1));
      expect(
        messages.single,
        startsWith('x.json:1:1: error GQL502: The schema file is not JSON: '),
      );
    });

    test('a JSON array is reported', () {
      expect(problems('x.json', '[]'), [
        'x.json:1:1: error GQL502: The schema file must hold a JSON object.',
      ]);
    });

    test('an object without __schema is reported at the file', () {
      final messages = problems('x.json', '{}');
      expect(messages, hasLength(1));
      expect(messages.single, startsWith('x.json:1:1: error GQL15'));
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/schema/schema_loader_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -518,4 +518,8 @@ enum DiagnosticCode(
   /// `GQL501`: a missing, unknown or mistyped key, or a malformed path or Dart
   /// reference, in the code generator's configuration.
   invalidConfig('GQL501'),
+
+  /// `GQL502`: a schema file the code generator cannot read as a schema: not
+  /// JSON, or JSON that is not an object.
+  invalidSchemaInput('GQL502'),
 }
```

Create `packages/typed_graphql_codegen/lib/src/project/project_file.dart`:

```dart
/// A file of the project the engine reads.
///
/// {@category codegen}
final class const ProjectFile(
  /// The path relative to the configuration file, with `/` separators.
  final String path,

  /// The content of the file.
  final String text,
) {
  /// Creates a file.
  this;

  @override
  bool operator ==(Object other) =>
      other is ProjectFile && other.path == path && other.text == text;

  @override
  int get hashCode => Object.hash(path, text);

  @override
  String toString() => 'ProjectFile($path)';
}
```

Create `packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Reads the text of an introspection result into a schema build.
final class const IntrospectionFileReader() {
  /// Creates a reader.
  this;

  /// Builds the schema [text] holds, a result or a response with a `data`
  /// member; every diagnostic has a place in [source].
  BuildResult read(String text, Source source) {
    final place = SourceSpan(source, 0, 0);
    return switch (const JsonReader().parse(text)) {
      DecodeFailure(:final message, :final path) => _failure(
        path.isEmpty
            ? 'The schema file is $message.'
            : 'The schema file is not valid JSON: '
                  '${DecodeFailure(message, path: path)}.',
        place,
      ),
      DecodeSuccess(value: final JsonObject object) => _build(object, place),
      DecodeSuccess() => _failure(
        'The schema file must hold a JSON object.',
        place,
      ),
    };
  }

  BuildResult _build(JsonObject object, SourceSpan place) {
    // A raw HTTP response wraps the result in `data`.
    final data = object['data'];
    final result = const SchemaBuilder(
      includesDeferAndStream: true,
    ).fromIntrospection(data is JsonObject ? data : object);
    return switch (result) {
      BuildSuccess() => result,
      BuildFailure(:final partial, :final diagnostics) => BuildFailure(
        partial,
        [for (final diagnostic in diagnostics) _placed(diagnostic, place)],
      ),
    };
  }

  BuildResult _failure(String message, SourceSpan place) => BuildFailure(
    Schema(),
    [Diagnostic(.invalidSchemaInput, .error, message, span: place)],
  );

  // The core's introspection diagnostics have no span; the file name is
  // what the CLI can print.
  Diagnostic _placed(Diagnostic diagnostic, SourceSpan place) =>
      diagnostic.span != null
      ? diagnostic
      : Diagnostic(
          diagnostic.code,
          diagnostic.severity,
          diagnostic.message,
          span: place,
          related: diagnostic.related,
        );
}
```

Create `packages/typed_graphql_codegen/lib/src/schema/schema_load_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The outcome of [SchemaLoader.load]: a valid schema or the problems that
/// stop one.
///
/// {@category codegen}
sealed class const SchemaLoadResult() {
  /// Creates a result.
  this;
}

/// A schema that was read, built and validated.
///
/// {@category codegen}
final class SchemaLoaded(
  /// The schema.
  final ValidSchema schema,
) extends SchemaLoadResult {
  /// Creates a result holding [schema].
  this;
}

/// A schema file with problems.
///
/// {@category codegen}
final class SchemaNotLoaded(
  List<Diagnostic> diagnostics,
) extends SchemaLoadResult {
  /// Creates a result with [diagnostics].
  this;

  /// The problems, in report order; they point into the file.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
```

Create `packages/typed_graphql_codegen/lib/src/schema/schema_loader.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';
import 'introspection_file_reader.dart';
import 'schema_load_result.dart';

/// Reads the schema file of a project: SDL, or an introspection result when
/// the path ends in `.json`.
///
/// {@category codegen}
final class const SchemaLoader() {
  /// Creates a loader.
  this;

  /// Builds and validates the schema [file] holds; never throws.
  SchemaLoadResult load(ProjectFile file) {
    final source = Source(file.text, name: file.path);
    final built = file.path.endsWith('.json')
        ? const IntrospectionFileReader().read(file.text, source)
        : _fromSdl(source);
    return switch (built) {
      BuildFailure(:final diagnostics) => SchemaNotLoaded(diagnostics),
      BuildSuccess(:final schema) => switch (const SchemaValidator().validate(
        schema,
      )) {
        final ValidSchema valid => SchemaLoaded(valid),
        InvalidSchema(:final diagnostics) => SchemaNotLoaded(diagnostics),
      },
    };
  }

  BuildResult _fromSdl(Source source) {
    // A schema is the developer's own file: only the operation token limit
    // is lifted. `@defer` is known so that the generator's own rule reports
    // it instead of an unknown directive.
    final parsed = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(source);
    return switch (parsed) {
      ParseFailure(:final diagnostics) => BuildFailure(Schema(), diagnostics),
      ParseSuccess(:final document) => const SchemaBuilder(
        includesDeferAndStream: true,
      ).fromSdl(document, source: source),
    };
  }
}
```

In `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -10,3 +10,6 @@ export 'src/config/config_result.dart';
 export 'src/config/dart_reference.dart';
 export 'src/config/scalar_mapping.dart';
 export 'src/config/schema_location.dart';
+export 'src/project/project_file.dart';
+export 'src/schema/schema_load_result.dart';
+export 'src/schema/schema_loader.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/schema/schema_loader_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- `SchemaLoader.load` reads the schema file (SDL, or an introspection result
  from a `.json` path) into a `ValidSchema`; a file that is not JSON or not a
  JSON object is `GQL502`.
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/lib/src/project/project_file.dart packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart packages/typed_graphql_codegen/lib/src/schema/schema_load_result.dart packages/typed_graphql_codegen/lib/src/schema/schema_loader.dart packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart packages/typed_graphql_codegen/test/schema/schema_loader_test.dart
git commit -q -m "feat(typed_graphql_codegen): load the schema from SDL or an introspection result" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Read the project's documents as one fragment graph

`ProjectDocuments.read(files)` parses each `.graphql` file with its own `Source` (the parser's limits per file, R1.6), so a syntax error is at `file:line:col`, then parses the joined text once more as the project document, in which every fragment is visible from every operation (R7.2, spec section 5). `ProjectSourceMap` maps project offsets, spans and diagnostics back to the file they came from.

Commit on the branch: `39d1af5`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/documents/project_documents.dart`, `packages/typed_graphql_codegen/lib/src/documents/project_documents_result.dart`, `packages/typed_graphql_codegen/lib/src/documents/project_source_map.dart`
- Test: `packages/typed_graphql_codegen/test/documents/project_documents_test.dart`, `packages/typed_graphql_codegen/test/documents/project_source_map_test.dart`

**Interfaces:**
- Consumes: Task 2 (`ProjectFile`); the core `Parser`, `Source`, `Diagnostic`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// documents/project_documents.dart
final class ProjectDocuments(…)
  static ProjectDocumentsResult read(List<ProjectFile> files)

// documents/project_documents_result.dart
sealed class ProjectDocumentsResult
  const ProjectDocumentsResult()
final class ProjectDocumentsRead(…)
final class ProjectDocumentsUnreadable(List<Diagnostic> diagnostics)

// documents/project_source_map.dart
final class ProjectSourceMap(List<ProjectFile> files)
  int fileIndexAt(int offset)
  String pathAt(int offset)
  SourceSpan translate(SourceSpan span)
  Diagnostic translateDiagnostic(Diagnostic diagnostic)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/documents/project_documents_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/documents/project_documents.dart';
import 'package:typed_graphql_codegen/src/documents/project_documents_result.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main() {
  ProjectDocuments read(List<ProjectFile> files) {
    final result = ProjectDocuments.read(files);
    if (result is! ProjectDocumentsRead) fail('expected success, got $result');
    return result.documents;
  }

  List<String> problems(List<ProjectFile> files) {
    final result = ProjectDocuments.read(files);
    if (result is! ProjectDocumentsUnreadable) fail('expected failure');
    return [for (final diagnostic in result.diagnostics) '$diagnostic'];
  }

  String names(int count, String prefix) =>
      [for (var i = 0; i < count; i++) '$prefix$i'].join(' ');

  const fileB = ProjectFile('b.graphql', 'fragment B on T { b }\n');
  const fileA = ProjectFile('a.graphql', 'fragment A on T { a }\n');

  test('files are sorted by path', () {
    final documents = read(const [fileB, fileA]);
    expect(
      [for (final file in documents.files) file.path],
      [
        'a.graphql',
        'b.graphql',
      ],
    );
  });

  test('the document has every definition in path order', () {
    final documents = read(const [fileB, fileA]);
    expect(
      [
        for (final definition in documents.document.definitions)
          (definition as FragmentDefinition).name.value,
      ],
      ['A', 'B'],
    );
  });

  test('a definition start maps back to its file and position', () {
    final documents = read(const [
      fileB,
      ProjectFile('a.graphql', '\n  fragment A on T { a }\n'),
    ]);
    final span = documents.sourceMap.translate(
      SourceSpan(
        documents.sourceMap.source,
        documents.document.definitions[0].start,
        documents.document.definitions[0].end,
      ),
    );
    expect('$span', 'a.graphql:2:3');
  });

  test('a syntax error is reported at its file', () {
    expect(
      problems([fileA, const ProjectFile('b.graphql', 'query {\n  a b: }')]),
      ['b.graphql:2:8: error GQL007: Expected Name, found "}".'],
    );
  });

  test('errors in two files are both reported, in path order', () {
    expect(
      problems(const [
        ProjectFile('b.graphql', '{'),
        ProjectFile('a.graphql', '{ a('),
      ]),
      [
        'a.graphql:1:5: error GQL007: Expected Name, found <EOF>.',
        'b.graphql:1:2: error GQL007: Expected Name, found <EOF>.',
      ],
    );
  });

  test('a file ending in a comment does not swallow the next file', () {
    final documents = read(const [
      ProjectFile('a.graphql', 'fragment A on T { a } # last'),
      fileB,
    ]);
    expect(documents.document.definitions, hasLength(2));
  });

  test('a file over the token limit fails with the token limit code', () {
    final text = 'query Q { ${names(15001, 'f')} }';
    final result = ProjectDocuments.read([ProjectFile('big.graphql', text)]);
    expect(
      result is ProjectDocumentsUnreadable &&
          result.diagnostics.single.code == DiagnosticCode.tokenLimitExceeded,
      isTrue,
    );
  });

  test('two files of 10000 tokens each succeed', () {
    final documents = read([
      ProjectFile('a.graphql', 'query A { ${names(9990, 'a')} }'),
      ProjectFile('b.graphql', 'query B { ${names(9990, 'b')} }'),
    ]);
    expect(documents.document.definitions, hasLength(2));
  });

  test('duplicate paths are an ArgumentError', () {
    expect(
      () => ProjectDocuments.read(const [fileA, fileA]),
      throwsArgumentError,
    );
  });

  test('no files give an empty document', () {
    expect(read(const []).document.definitions, isEmpty);
  });
}
```

Create `packages/typed_graphql_codegen/test/documents/project_source_map_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/documents/project_source_map.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main() {
  // Starts: a.graphql 0 (length 3), b.graphql 4 (length 5), c.graphql 10.
  final map = ProjectSourceMap(const [
    ProjectFile('a.graphql', 'abc'),
    ProjectFile('b.graphql', 'de\nfg'),
    ProjectFile('c.graphql', 'hi'),
  ]);

  test('the project text joins the files with line breaks', () {
    expect(map.text, 'abc\nde\nfg\nhi\n');
  });

  test('an offset in the first file maps to it', () {
    expect(map.pathAt(1), 'a.graphql');
  });

  test('an offset in the middle file maps to it', () {
    expect(map.pathAt(7), 'b.graphql');
  });

  test('an offset in the last file maps to it', () {
    expect(map.pathAt(11), 'c.graphql');
  });

  test('an offset on the joining line break belongs to the file before', () {
    expect(map.fileIndexAt(3), 0);
  });

  test('a span is translated into its file', () {
    final span = map.translate(SourceSpan(map.source, 7, 9));
    expect(['$span', span.text], ['b.graphql:2:1', 'fg']);
  });

  test('a span on the joining line break is clamped to the file', () {
    final span = map.translate(SourceSpan(map.source, 2, 4));
    expect([span.start, span.end, span.text], [2, 3, 'c']);
  });

  test('a span of another source is kept', () {
    final span = SourceSpan(Source('x', name: 'other'), 0, 1);
    expect(identical(map.translate(span), span), isTrue);
  });

  test('a diagnostic and its related spans are translated', () {
    final diagnostic = Diagnostic(
      DiagnosticCode.expectedToken,
      DiagnosticSeverity.error,
      'message',
      span: SourceSpan(map.source, 11, 12),
      related: [SourceSpan(map.source, 5, 6)],
    );
    final translated = map.translateDiagnostic(diagnostic);
    expect(
      [
        '${translated.span}',
        for (final place in translated.related) '$place',
        translated.code,
        translated.message,
      ],
      [
        'c.graphql:1:2',
        'b.graphql:1:2',
        DiagnosticCode.expectedToken,
        'message',
      ],
    );
  });

  test('a diagnostic without a span stays without one', () {
    final diagnostic = Diagnostic(
      DiagnosticCode.expectedToken,
      DiagnosticSeverity.error,
      'message',
    );
    expect(map.translateDiagnostic(diagnostic), diagnostic);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/documents/project_documents_test.dart test/documents/project_source_map_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_codegen/lib/src/documents/project_documents.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';
import 'project_documents_result.dart';
import 'project_source_map.dart';

/// The project's `.graphql` files read as one document, so that a fragment
/// is visible from every operation (R7.2).
///
/// The document's offsets index [ProjectSourceMap.source]; the map gives the
/// file of each offset.
final class ProjectDocuments(
  /// The files, sorted by path.
  final List<ProjectFile> files,

  /// The map from project offsets to files.
  final ProjectSourceMap sourceMap,

  /// Every definition of every file, in path order.
  final Document document,
) {
  /// Creates the documents.
  this;

  /// Parses [files]; two files with one path are an [ArgumentError].
  static ProjectDocumentsResult read(List<ProjectFile> files) {
    final sorted = [...files]..sort((a, b) => a.path.compareTo(b.path));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].path == sorted[i - 1].path) {
        throw ArgumentError.value(
          files,
          'files',
          'two files have the path ${sorted[i].path}',
        );
      }
    }
    final problems = _parseEach(sorted);
    if (problems.isNotEmpty) {
      return ProjectDocumentsUnreadable(problems);
    }
    final map = ProjectSourceMap(sorted);
    if (sorted.isEmpty) {
      // An empty text is a syntax error, so the empty document is built.
      return ProjectDocumentsRead(
        ProjectDocuments(sorted, map, Document(const [])),
      );
    }
    // Each file parsed alone and ends at a token boundary, and the joining
    // line break ends a trailing comment, so the whole cannot fail; the
    // branch is defensive.
    final whole = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(map.source);
    return switch (whole) {
      ParseSuccess(:final document) => ProjectDocumentsRead(
        ProjectDocuments(sorted, map, document),
      ),
      ParseFailure(:final diagnostics) => ProjectDocumentsUnreadable([
        for (final diagnostic in diagnostics)
          map.translateDiagnostic(diagnostic),
      ]),
    };
  }

  // Every file is parsed before reporting: a missing fragment would turn each
  // spread of it into a second, misleading error.
  static List<Diagnostic> _parseEach(List<ProjectFile> sorted) {
    final problems = <Diagnostic>[];
    for (final file in sorted) {
      final result = const Parser().parse(Source(file.text, name: file.path));
      if (result is ParseFailure) {
        problems.addAll(result.diagnostics);
      }
    }
    return problems;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/documents/project_documents_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'project_documents.dart';

/// The result of reading the project's documents: [ProjectDocumentsRead] or
/// [ProjectDocumentsUnreadable].
sealed class ProjectDocumentsResult {
  /// Creates a result.
  const ProjectDocumentsResult();
}

/// Every file parsed.
final class ProjectDocumentsRead(
  /// The documents as one fragment graph.
  final ProjectDocuments documents,
) extends ProjectDocumentsResult {
  /// Creates a success.
  this;
}

/// At least one file has a syntax error.
final class ProjectDocumentsUnreadable(List<Diagnostic> diagnostics)
    extends ProjectDocumentsResult {
  /// Creates a failure.
  this;

  /// Every diagnostic of every file that failed, in path order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
```

Create `packages/typed_graphql_codegen/lib/src/documents/project_source_map.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';

/// Maps offsets of the project text, every file joined by a line break, back
/// to the file they came from.
///
/// Each file occupies `[start, start + text.length]` of [text]; the line
/// break after it belongs to that file, so an offset on it maps to the file
/// before it.
final class ProjectSourceMap(List<ProjectFile> files) {
  /// Creates a map of [files], which are already in project order.
  this;

  final List<Source> _sources = [
    for (final file in files) Source(file.text, name: file.path),
  ];

  final List<int> _starts = _startsOf(files);

  /// The project text: every file's text followed by a line break.
  final String text = [for (final file in files) '${file.text}\n'].join();

  /// The project text as one [Source], named `<project>`.
  // late: it reads [text], which is initialised before the first access.
  late final Source source = Source(text, name: '<project>');

  static List<int> _startsOf(List<ProjectFile> files) {
    final starts = <int>[];
    var offset = 0;
    for (final file in files) {
      starts.add(offset);
      offset += file.text.length + 1;
    }
    return starts;
  }

  /// The index of the file that holds [offset].
  int fileIndexAt(int offset) {
    RangeError.checkValueInInterval(offset, 0, text.length, 'offset');
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// The path of the file that holds [offset].
  String pathAt(int offset) => _sources[fileIndexAt(offset)].name;

  /// [span] of the project source as a span of its file.
  ///
  /// A span from another source is returned as it is.
  SourceSpan translate(SourceSpan span) {
    if (!identical(span.source, source)) {
      return span;
    }
    final index = fileIndexAt(span.start);
    final fileSource = _sources[index];
    final fileStart = _starts[index];
    final end = span.end - fileStart;
    return SourceSpan(
      fileSource,
      span.start - fileStart,
      // A span can end on the joining line break, which is not in the file.
      end > fileSource.body.length ? fileSource.body.length : end,
    );
  }

  /// [diagnostic] with its span and related spans translated by [translate].
  Diagnostic translateDiagnostic(Diagnostic diagnostic) {
    final span = diagnostic.span;
    return Diagnostic(
      diagnostic.code,
      diagnostic.severity,
      diagnostic.message,
      span: span == null ? null : translate(span),
      related: [for (final place in diagnostic.related) translate(place)],
    );
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/documents/project_documents_test.dart test/documents/project_source_map_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_codegen/lib/src/documents/project_documents.dart packages/typed_graphql_codegen/lib/src/documents/project_documents_result.dart packages/typed_graphql_codegen/lib/src/documents/project_source_map.dart packages/typed_graphql_codegen/test/documents/project_documents_test.dart packages/typed_graphql_codegen/test/documents/project_source_map_test.dart
git commit -q -m "feat(typed_graphql_codegen): read the project's documents as one fragment graph" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Add the code generator's document and mapping codes

The core catalog gains `GQL503` anonymousOperation, `GQL504` unsupportedInDocument, `GQL505` unknownScalarMapping and `GQL506` noDocuments (a warning), in id order with their doc comments, in a commit of their own before Task 5 reports them.

Commit on the branch: `0d64068`.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: The core `DiagnosticCode`.
- Produces:
- Diagnostic codes: `GQL503`, `GQL504`, `GQL505`, `GQL506`.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -522,4 +522,21 @@ enum DiagnosticCode(
   /// `GQL502`: a schema file the code generator cannot read as a schema: not
   /// JSON, or JSON that is not an object.
   invalidSchemaInput('GQL502'),
+
+  /// `GQL503`: an operation without a name in a document the code generator
+  /// reads; its classes are named after the operation.
+  anonymousOperation('GQL503'),
+
+  /// `GQL504`: a construct the code generator does not support yet: `@defer`,
+  /// `@stream`, or a fragment on an abstract type spread at the root of a
+  /// subscription.
+  unsupportedInDocument('GQL504'),
+
+  /// `GQL505`: the configuration maps a scalar the schema does not have as a
+  /// custom scalar: unknown, not a scalar, or built in.
+  unknownScalarMapping('GQL505'),
+
+  /// `GQL506`: no document matches the configuration's `documents`; reported
+  /// as a warning.
+  noDocuments('GQL506'),
 }
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
git commit -q -m "feat(typed_graphql): add the code generator's document and mapping codes" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Check the schema and the documents

`ClientGenerator.check` loads the schema (`ClientProjectLoader`), checks the scalar mappings (`ScalarMappingChecker`, `GQL505`; `ScalarMapping` now keeps the place of its key) and validates the project document with `ClientGenerator.rules`: the specified rules minus `NoUnusedFragmentsRule` and `LoneAnonymousOperationRule`, plus `NamedOperationsRule` (`GQL503`) and `UnsupportedDirectivesRule` (`GQL504`, `@defer` and `@stream`). No document is `GQL506`. `engine_imports_test.dart` pins that no library outside `lib/src/cli/` imports `dart:io`.

Commit on the branch: `dd1152d`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, `packages/typed_graphql_codegen/lib/src/generator/client_project.dart`, `packages/typed_graphql_codegen/lib/src/generator/client_project_loader.dart`, `packages/typed_graphql_codegen/lib/src/generator/client_project_result.dart`, `packages/typed_graphql_codegen/lib/src/generator/rules/named_operations_rule.dart`, `packages/typed_graphql_codegen/lib/src/generator/rules/unsupported_directives_rule.dart`, `packages/typed_graphql_codegen/lib/src/generator/scalar_mapping_checker.dart`
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/lib/src/config/config_report.dart`, `packages/typed_graphql_codegen/lib/src/config/scalar_mapping.dart`, `packages/typed_graphql_codegen/lib/src/config/scalar_mapping_reader.dart`, `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`
- Test: `packages/typed_graphql_codegen/test/config/codegen_config_test.dart`, `packages/typed_graphql_codegen/test/generator/client_generator_test.dart`, `packages/typed_graphql_codegen/test/quality/engine_imports_test.dart`

**Interfaces:**
- Consumes: Tasks 1-4; the core `DocumentValidator`, `ValidationRule`, `ValidationContext`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// config/config_report.dart
  SourceSpan spanOf(YamlNode node)

// generator/client_generator.dart
final class const ClientGenerator(final CodegenConfig config)
  List<Diagnostic> check({

// generator/client_project.dart
final class ClientProject(…)

// generator/client_project_loader.dart
final class const ClientProjectLoader(final CodegenConfig config)
  ClientProjectResult load({

// generator/client_project_result.dart
sealed class ClientProjectResult
  const ClientProjectResult()
final class ClientProjectLoaded(…)
final class ClientProjectFailed(List<Diagnostic> diagnostics)

// generator/rules/named_operations_rule.dart
final class const NamedOperationsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _NamedOperations(final ValidationContext context)
  VisitAction enter(Node node)

// generator/rules/unsupported_directives_rule.dart
final class const UnsupportedDirectivesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _UnsupportedDirectives(final ValidationContext context)
  VisitAction enter(Node node)

// generator/scalar_mapping_checker.dart
final class const ScalarMappingChecker()
  List<Diagnostic> check(CodegenConfig config, Schema schema)
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/config/codegen_config_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -106,6 +106,14 @@ scalars:
       );
     });
 
+    test('a scalar mapping keeps the place of its key', () {
+      final config = read(
+        'schema: s.graphql\nscalars:\n  Moment:\n    type: DateTime\n'
+        '    codec: package:a/a.dart#C\n',
+      );
+      expect('${config.scalars['Moment']!.span}', '$_path:3:3');
+    });
+
     test('the maps are unmodifiable', () {
       final config = read('schema: https://h.dev/g\nheaders:\n  A: b\n');
       expect(() => config.headers['C'] = 'd', throwsUnsupportedError);
```

Create `packages/typed_graphql_codegen/test/generator/client_generator_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/generator/rules/named_operations_rule.dart';
import 'package:typed_graphql_codegen/src/generator/rules/unsupported_directives_rule.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
type Query {
  hello: String
  user: User
}

type User {
  name: String
}

scalar Moment
''');

const _aFile = ProjectFile(
  'a.graphql',
  'query A {\n  user {\n    ...Name\n  }\n}\n',
);

const _bFile = ProjectFile(
  'b.graphql',
  'fragment Name on User {\n  name\n}\n',
);

void main() {
  CodegenConfig configOf(String text) {
    final result = CodegenConfig.parse(text, path: 'typed_graphql.yaml');
    if (result is! ConfigSuccess) fail('expected success, got $result');
    return result.config;
  }

  List<String> check(
    List<ProjectFile> documents, {
    ProjectFile schema = _schema,
    String config = 'schema: schema.graphql\n',
  }) {
    final diagnostics = ClientGenerator(
      configOf(config),
    ).check(schema: schema, documents: documents);
    return [
      for (final diagnostic in diagnostics)
        [
          '$diagnostic',
          for (final place in diagnostic.related) 'also $place',
        ].join(' | '),
    ];
  }

  group('documents', () {
    test('a valid project has no diagnostics', () {
      expect(check(const [_aFile, _bFile]), isEmpty);
    });

    test('an unknown field is reported in its file', () {
      expect(
        check(const [
          _aFile,
          ProjectFile('b.graphql', 'fragment Name on User {\n  nam\n}\n'),
        ]),
        [
          'b.graphql:2:3: error GQL205: Cannot query field "nam" on type '
              '"User". Did you mean "name"?',
        ],
      );
    });

    test('an unused fragment is not an error', () {
      expect(
        check(const [
          ProjectFile('a.graphql', 'query A { hello }\n'),
          _bFile,
        ]),
        isEmpty,
      );
    });

    test('an anonymous operation needs a name', () {
      expect(check(const [ProjectFile('a.graphql', '{ hello }\n')]), [
        'a.graphql:1:1: error GQL503: An operation needs a name: its classes '
            'are named after it.',
      ]);
    });

    test('two anonymous operations are each reported', () {
      expect(
        check(const [
          ProjectFile('a.graphql', '{ hello }\n'),
          ProjectFile('b.graphql', 'query { hello }\n'),
        ]),
        [
          'a.graphql:1:1: error GQL503: An operation needs a name: its '
              'classes are named after it.',
          'b.graphql:1:1: error GQL503: An operation needs a name: its '
              'classes are named after it.',
        ],
      );
    });

    test('@defer is not supported yet', () {
      expect(
        check(const [
          _aFile,
          ProjectFile(
            'b.graphql',
            'fragment Name on User {\n  ... @defer {\n    name\n  }\n}\n',
          ),
        ]),
        [
          'b.graphql:2:7: error GQL504: The code generator does not support '
              "'@defer' yet.",
        ],
      );
    });

    test('@stream is not supported yet', () {
      final schema = ProjectFile(
        'schema.graphql',
        '${_schema.text}type Other { names: [String] }\n'
            'extend type Query { other: Other }\n',
      );
      expect(
        check(const [
          ProjectFile(
            'a.graphql',
            'query A {\n  other {\n    names @stream\n  }\n}\n',
          ),
        ], schema: schema),
        [
          'a.graphql:3:11: error GQL504: The code generator does not support '
              "'@stream' yet.",
        ],
      );
    });

    test('an operation name used in two files is reported in both', () {
      expect(
        check(const [
          ProjectFile('a.graphql', 'query A { hello }\n'),
          ProjectFile('b.graphql', 'query A { user { name } }\n'),
        ]),
        [
          'a.graphql:1:7: error GQL202: There can be only one operation '
              'named "A". | also b.graphql:1:7',
        ],
      );
    });

    test('a fragment defined in one file is spread in another', () {
      expect(check(const [_bFile, _aFile]), isEmpty);
    });
  });

  group('scalar mappings', () {
    const mappings = '''
schema: schema.graphql
scalars:
  Moment:
    type: DateTime
    codec: package:a/a.dart#C
''';

    String mapping(String name) =>
        'schema: schema.graphql\nscalars:\n  $name:\n    type: DateTime\n'
        '    codec: package:a/a.dart#C\n';

    test('a custom scalar of the schema may be mapped', () {
      expect(check(const [_aFile, _bFile], config: mappings), isEmpty);
    });

    test('an unknown scalar is reported at its key', () {
      expect(check(const [_aFile, _bFile], config: mapping('Foo')), [
        "typed_graphql.yaml:3:3: error GQL505: No scalar 'Foo' in the "
            'schema to map.',
      ]);
    });

    test('an object type is not a scalar', () {
      expect(check(const [_aFile, _bFile], config: mapping('User')), [
        "typed_graphql.yaml:3:3: error GQL505: 'User' is not a scalar, so "
            'it cannot be mapped.',
      ]);
    });

    test('a built-in scalar cannot be mapped', () {
      expect(check(const [_aFile, _bFile], config: mapping('Int')), [
        "typed_graphql.yaml:3:3: error GQL505: The built-in scalar 'Int' "
            'cannot be mapped.',
      ]);
    });

    test('a mapping error is listed before the documents errors', () {
      expect(
        check(const [
          ProjectFile('a.graphql', '{ hello }\n'),
        ], config: mapping('Foo')),
        [
          "typed_graphql.yaml:3:3: error GQL505: No scalar 'Foo' in the "
              'schema to map.',
          'a.graphql:1:1: error GQL503: An operation needs a name: its '
              'classes are named after it.',
        ],
      );
    });
  });

  group('inputs', () {
    test('no documents is one warning without a place', () {
      expect(check(const []), [
        "warning GQL506: No document matches the configuration's "
            "'documents'.",
      ]);
    });

    test('a broken schema is reported with the documents syntax errors', () {
      expect(
        check(
          const [ProjectFile('a.graphql', 'query A { hello\n')],
          schema: const ProjectFile('schema.graphql', 'type Query {\n'),
        ),
        [
          'schema.graphql:2:1: error GQL007: Expected Name, found <EOF>.',
          'a.graphql:2:1: error GQL007: Expected Name, found <EOF>.',
        ],
      );
    });

    test('a syntax error in a document stops validation', () {
      expect(check(const [ProjectFile('a.graphql', 'query A { \n')]), [
        'a.graphql:2:1: error GQL007: Expected Name, found <EOF>.',
      ]);
    });
  });

  group('rules', () {
    test('are the specified rules, minus two, plus the generator\'s', () {
      const dropped = {NoUnusedFragmentsRule, LoneAnonymousOperationRule};
      expect(
        [for (final rule in ClientGenerator.rules) rule.runtimeType],
        [
          for (final rule in DocumentValidator.specifiedRules)
            if (!dropped.contains(rule.runtimeType)) rule.runtimeType,
          NamedOperationsRule,
          UnsupportedDirectivesRule,
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_codegen/test/quality/engine_imports_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no library outside lib/src/cli imports dart:io', () {
    final offenders = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.startsWith('lib/src/cli/') &&
            RegExp(
              r'''^\s*(import|export)\s+['"]dart:io['"]''',
              multiLine: true,
            ).hasMatch(entity.readAsStringSync()))
          entity.path,
    ];
    expect(offenders, isEmpty);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/config/codegen_config_test.dart test/generator/client_generator_test.dart test/quality/engine_imports_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/config/config_report.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,6 +16,10 @@ final class ConfigReport(
   /// Whether no problem was reported.
   bool get isClean => diagnostics.isEmpty;
 
+  /// The place of [node] in the configuration file.
+  SourceSpan spanOf(YamlNode node) =>
+      SourceSpan(source, node.span.start.offset, node.span.end.offset);
+
   /// Reports [message] at [node].
   void error(YamlNode node, String message) {
     diagnostics.add(
@@ -23,7 +27,7 @@ final class ConfigReport(
         .invalidConfig,
         .error,
         message,
-        span: SourceSpan(source, node.span.start.offset, node.span.end.offset),
+        span: spanOf(node),
       ),
     );
   }
```

In `packages/typed_graphql_codegen/lib/src/config/scalar_mapping.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,5 @@
+import 'package:typed_graphql/typed_graphql.dart';
+
 import 'dart_reference.dart';
 
 /// How generated code holds a custom scalar (R7.8): its Dart [type] and the
@@ -10,8 +12,13 @@ final class const ScalarMapping(
   final DartReference type,
 
   /// The codec class, constructed as `const Codec()` in generated code.
-  final DartReference codec,
-) {
+  final DartReference codec, {
+
+  /// The scalar's key in the configuration file, where a problem with the
+  /// mapping is reported; null for a mapping built in code. It takes no part
+  /// in `==` and `hashCode`.
+  final SourceSpan? span,
+}) {
   /// Creates a mapping to [type] through [codec].
   this;
 
```

In `packages/typed_graphql_codegen/lib/src/config/scalar_mapping_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -27,7 +27,7 @@ final class const ScalarMappingReader() {
         report.error(key, 'A scalar name must be a GraphQL name.');
         continue;
       }
-      final mapping = _readMapping(text, value, report);
+      final mapping = _readMapping(text, key, value, report);
       if (mapping != null) mappings[text] = mapping;
     }
     return {
@@ -35,7 +35,12 @@ final class const ScalarMappingReader() {
     };
   }
 
-  ScalarMapping? _readMapping(String name, YamlNode node, ConfigReport report) {
+  ScalarMapping? _readMapping(
+    String name,
+    YamlNode key,
+    YamlNode node,
+    ConfigReport report,
+  ) {
     if (node is! YamlMap) {
       report.error(
         node,
@@ -43,6 +48,19 @@ final class const ScalarMappingReader() {
       );
       return null;
     }
+    final (:type, :codec, :isValid) = _readKeys(name, node, report);
+    final hasAll = _hasRequiredKeys(name, node, report);
+    if (isValid && hasAll && type != null && codec != null) {
+      return ScalarMapping(type, codec, span: report.spanOf(key));
+    }
+    return null;
+  }
+
+  ({DartReference? type, DartReference? codec, bool isValid}) _readKeys(
+    String name,
+    YamlMap node,
+    ConfigReport report,
+  ) {
     DartReference? type;
     DartReference? codec;
     var isValid = true;
@@ -69,11 +87,7 @@ final class const ScalarMappingReader() {
           isValid = false;
       }
     }
-    isValid = _hasRequiredKeys(name, node, report) && isValid;
-    if (isValid && type != null && codec != null) {
-      return ScalarMapping(type, codec);
-    }
-    return null;
+    return (type: type, codec: codec, isValid: isValid);
   }
 
   bool _hasRequiredKeys(String name, YamlMap node, ConfigReport report) {
```

Create `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../project/project_file.dart';
import 'client_project_loader.dart';
import 'client_project_result.dart';
import 'rules/named_operations_rule.dart';
import 'rules/unsupported_directives_rule.dart';

/// Generates typed Dart client code from a schema and `.graphql` documents.
///
/// {@category codegen}
final class const ClientGenerator(final CodegenConfig config) {
  /// Creates a generator for [config].
  this;

  /// The rules the project's documents are validated with.
  ///
  /// [DocumentValidator.specifiedRules] without [NoUnusedFragmentsRule] (a
  /// fragment may exist for the application's own reads) and
  /// [LoneAnonymousOperationRule] (operations must be named anyway), then the
  /// generator's own rules.
  static const List<ValidationRule> rules = [
    ExecutableDefinitionsRule(),
    KnownOperationTypesRule(),
    UniqueOperationNamesRule(),
    SingleFieldSubscriptionsRule(),
    KnownTypeNamesRule(),
    FragmentsOnCompositeTypesRule(),
    VariablesAreInputTypesRule(),
    ScalarLeafsRule(),
    FieldsOnCorrectTypeRule(),
    UniqueFragmentNamesRule(),
    KnownFragmentNamesRule(),
    PossibleFragmentSpreadsRule(),
    NoFragmentCyclesRule(),
    UniqueVariableNamesRule(),
    NoUndefinedVariablesRule(),
    NoUnusedVariablesRule(),
    KnownDirectivesRule(),
    DirectivesInValidLocationsRule(),
    UniqueDirectivesPerLocationRule(),
    KnownArgumentNamesRule(),
    UniqueArgumentNamesRule(),
    ValuesOfCorrectTypeRule(),
    InputObjectFieldNamesRule(),
    InputObjectRequiredFieldsRule(),
    ProvidedRequiredArgumentsRule(),
    VariablesInAllowedPositionRule(),
    OverlappingFieldsCanBeMergedRule(),
    UniqueInputFieldNamesRule(),
    NamedOperationsRule(),
    UnsupportedDirectivesRule(),
  ];

  /// Checks the schema and the documents as `generate` will read them;
  /// returns every diagnostic, warnings included, in report order.
  ///
  /// [schema] is the schema file and [documents] the files the configuration's
  /// `documents` globs matched; nothing is written.
  List<Diagnostic> check({
    required ProjectFile schema,
    required List<ProjectFile> documents,
  }) {
    final result = ClientProjectLoader(
      config,
    ).load(schema: schema, documents: documents);
    return switch (result) {
      ClientProjectLoaded(:final warnings) => warnings,
      ClientProjectFailed(:final diagnostics) => diagnostics,
    };
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/client_project.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../documents/project_documents.dart';

/// A schema and the documents validated against it: what the generator reads.
final class ClientProject(
  /// The valid schema.
  final ValidSchema schema,

  /// The project's documents as one fragment graph.
  final ProjectDocuments documents,

  /// The documents, validated with `ClientGenerator.rules`.
  final ValidDocument document,
) {
  /// Creates a project.
  this;
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/client_project_loader.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../documents/project_documents.dart';
import '../documents/project_documents_result.dart';
import '../project/project_file.dart';
import '../schema/schema_load_result.dart';
import '../schema/schema_loader.dart';
import 'client_generator.dart';
import 'client_project.dart';
import 'client_project_result.dart';
import 'scalar_mapping_checker.dart';

/// Reads the schema and the documents of a project and validates them with
/// [ClientGenerator.rules]; shared by `check` and `generate`.
final class const ClientProjectLoader(final CodegenConfig config) {
  /// Creates a loader for [config].
  this;

  /// Loads the project; never throws for bad input.
  ClientProjectResult load({
    required ProjectFile schema,
    required List<ProjectFile> documents,
  }) {
    final read = ProjectDocuments.read(documents);
    final loaded = const SchemaLoader().load(schema);
    if (loaded is! SchemaLoaded) {
      // The documents are read anyway so that one run shows every syntax
      // error.
      return ClientProjectFailed([
        if (loaded is SchemaNotLoaded) ...loaded.diagnostics,
        if (read is ProjectDocumentsUnreadable) ...read.diagnostics,
      ]);
    }
    final mapping = const ScalarMappingChecker().check(
      config,
      loaded.schema.schema,
    );
    return switch (read) {
      ProjectDocumentsUnreadable(:final diagnostics) => ClientProjectFailed([
        ...mapping,
        ...diagnostics,
      ]),
      ProjectDocumentsRead(documents: final files) => _validate(
        loaded.schema,
        files,
        mapping,
      ),
    };
  }

  ClientProjectResult _validate(
    ValidSchema schema,
    ProjectDocuments documents,
    List<Diagnostic> mapping,
  ) {
    final warnings = <Diagnostic>[
      if (documents.files.isEmpty)
        Diagnostic(
          .noDocuments,
          .warning,
          "No document matches the configuration's 'documents'.",
        ),
    ];
    final map = documents.sourceMap;
    final result = const DocumentValidator(rules: ClientGenerator.rules)
        .validate(schema, documents.document, source: map.source);
    return switch (result) {
      InvalidDocument(:final diagnostics) => ClientProjectFailed([
        ...mapping,
        for (final diagnostic in diagnostics)
          map.translateDiagnostic(diagnostic),
        ...warnings,
      ]),
      ValidDocument() when mapping.isNotEmpty => ClientProjectFailed([
        ...mapping,
        ...warnings,
      ]),
      final ValidDocument valid => ClientProjectLoaded(
        ClientProject(schema, documents, valid),
        warnings,
      ),
    };
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/client_project_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'client_project.dart';

/// The outcome of loading a project: [ClientProjectLoaded] or
/// [ClientProjectFailed].
sealed class ClientProjectResult {
  /// Creates a result.
  const ClientProjectResult();
}

/// A project that can be generated from.
final class ClientProjectLoaded(
  /// The project.
  final ClientProject project,
  List<Diagnostic> warnings,
) extends ClientProjectResult {
  /// Creates a success.
  this;

  /// The warnings, in report order.
  final List<Diagnostic> warnings = List.unmodifiable(warnings);
}

/// A project with errors.
final class ClientProjectFailed(List<Diagnostic> diagnostics)
    extends ClientProjectResult {
  /// Creates a failure.
  this;

  /// Every diagnostic, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/rules/named_operations_rule.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// `GQL503`: every operation has a name, because the generated classes are
/// named after it.
final class const NamedOperationsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NamedOperations(context);
}

final class _NamedOperations(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition(name: null):
        context.report(
          .anonymousOperation,
          'An operation needs a name: its classes are named after it.',
          [node],
        );
        return .skip;
      case ExecutableDefinition():
        return .skip;
      default:
        return .next;
    }
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/rules/unsupported_directives_rule.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// `GQL504`: `@defer` and `@stream` are not generated yet.
final class const UnsupportedDirectivesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UnsupportedDirectives(context);
}

final class _UnsupportedDirectives(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case Directive(name: Name(:final value))
        when value == 'defer' || value == 'stream') {
      context.report(
        .unsupportedInDocument,
        "The code generator does not support '@$value' yet.",
        [node],
      );
      return .skip;
    }
    return .next;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/scalar_mapping_checker.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';

/// Checks that each scalar the configuration maps is a custom scalar of the
/// schema (`GQL505`).
final class const ScalarMappingChecker() {
  /// Creates the checker.
  this;

  static const _builtIn = {'Int', 'Float', 'String', 'Boolean', 'ID'};

  /// The problems of [config]'s mappings against [schema], in name order.
  List<Diagnostic> check(CodegenConfig config, Schema schema) {
    final problems = <Diagnostic>[];
    for (final MapEntry(:key, :value) in config.scalars.entries) {
      final message = _problemWith(key, schema);
      if (message != null) {
        problems.add(
          Diagnostic(.unknownScalarMapping, .error, message, span: value.span),
        );
      }
    }
    return problems;
  }

  String? _problemWith(String name, Schema schema) {
    if (_builtIn.contains(name)) {
      return "The built-in scalar '$name' cannot be mapped.";
    }
    return switch (schema.typeNamed(name)) {
      null => "No scalar '$name' in the schema to map.",
      ScalarType() => null,
      _ => "'$name' is not a scalar, so it cannot be mapped.",
    };
  }
}
```

In `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -10,6 +10,7 @@ export 'src/config/config_result.dart';
 export 'src/config/dart_reference.dart';
 export 'src/config/scalar_mapping.dart';
 export 'src/config/schema_location.dart';
+export 'src/generator/client_generator.dart';
 export 'src/project/project_file.dart';
 export 'src/schema/schema_load_result.dart';
 export 'src/schema/schema_loader.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/config/codegen_config_test.dart test/generator/client_generator_test.dart test/quality/engine_imports_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- `ClientGenerator.check` validates the schema, the scalar mappings and the
  documents of a project (`GQL503`-`GQL506`); `ClientGenerator.rules` are the
  specified rules without the unused-fragment and lone-anonymous rules, plus
  named operations and no `@defer`/`@stream`.
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/lib/src/config/config_report.dart packages/typed_graphql_codegen/lib/src/config/scalar_mapping.dart packages/typed_graphql_codegen/lib/src/config/scalar_mapping_reader.dart packages/typed_graphql_codegen/lib/src/generator/client_generator.dart packages/typed_graphql_codegen/lib/src/generator/client_project.dart packages/typed_graphql_codegen/lib/src/generator/client_project_loader.dart packages/typed_graphql_codegen/lib/src/generator/client_project_result.dart packages/typed_graphql_codegen/lib/src/generator/rules/named_operations_rule.dart packages/typed_graphql_codegen/lib/src/generator/rules/unsupported_directives_rule.dart packages/typed_graphql_codegen/lib/src/generator/scalar_mapping_checker.dart packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart packages/typed_graphql_codegen/test/config/codegen_config_test.dart packages/typed_graphql_codegen/test/generator/client_generator_test.dart packages/typed_graphql_codegen/test/quality/engine_imports_test.dart
git commit -q -m "feat(typed_graphql_codegen): check the schema and the documents" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Add the Client Code Generation guide

The package's guide `doc/client_codegen.md` (configuration keys, a checking program whose output the documentation suite runs, the codes `GQL500`-`GQL506`), the `codegen` dartdoc category and a documentation suite that reuses the core's snippet runner, link checker and category-tag scanner. The README, `llms.txt` and the root README say the package checks a project and does not generate code yet.

Commit on the branch: `ba3d924`.

**Files:**
- Create: `packages/typed_graphql_codegen/dartdoc_options.yaml`, `packages/typed_graphql_codegen/doc/client_codegen.md`
- Modify: `README.md`, `llms.txt`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/README.md`
- Test: `packages/typed_graphql_codegen/test/doc/category_tags_test.dart`, `packages/typed_graphql_codegen/test/doc/guide_links_test.dart`, `packages/typed_graphql_codegen/test/doc/guide_snippets_test.dart`

**Interfaces:**
- Consumes: Tasks 1-5 (the public API the guide shows); the core `test/doc/` support.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/doc/category_tags_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../typed_graphql/test/doc/public_type.dart';

/// Every exported type is in the `codegen` dartdoc category, which
/// `dartdoc_options.yaml` declares with its guide (R11.2).
void main() {
  final barrel = File('lib/typed_graphql_codegen.dart').readAsStringSync();
  final exported = [
    for (final match in RegExp("export '([^']+)';").allMatches(barrel))
      match[1]!,
  ];
  final options = File('dartdoc_options.yaml').readAsStringSync();

  test('the only category declared is codegen', () {
    final declared = [
      for (final match in RegExp(
        r'^ {4}([a-z-]+):$',
        multiLine: true,
      ).allMatches(options))
        match[1]!,
    ];
    expect(declared, ['codegen']);
  });

  test('the category has its guide', () {
    expect(options, contains('markdown: doc/client_codegen.md'));
    expect(File('doc/client_codegen.md').existsSync(), isTrue);
  });

  group('exported types', () {
    for (final path in exported) {
      test(path, () {
        final source = File('lib/$path').readAsStringSync();
        final untagged = [
          for (final type in const PublicTypes().declaredIn(source))
            if (type.countOf('{@category codegen}') != 1) type.name,
        ];
        expect(
          untagged,
          isEmpty,
          reason: 'give each exactly one {@category codegen} in its doc',
        );
      });
    }
  });
}
```

Create `packages/typed_graphql_codegen/test/doc/guide_links_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';

import '../../../typed_graphql/test/doc/doc_files.dart';
import '../../../typed_graphql/test/doc/markdown_links.dart';

/// Every relative link of the guide and the READMEs leads somewhere (R11.1,
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
```

Create `packages/typed_graphql_codegen/test/doc/guide_snippets_test.dart`:

```dart
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
```

- [ ] **Step 2: Update the package files**

Create `packages/typed_graphql_codegen/dartdoc_options.yaml`:

```yaml
dartdoc:
  categories:
    codegen:
      markdown: doc/client_codegen.md
      displayName: Client Code Generation
  categoryOrder:
    - codegen
  showUndocumentedCategories: true
```

- [ ] **Step 3: Update the documents**

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -113,7 +113,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
-| [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | skeleton (M8, M10) |
+| [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
 | [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
 | [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language, schema and introspection suites, fuzzers (M2, M3) |
 
```

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,7 +7,7 @@
 - [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, operation validation with opt-in limits and cost analysis, wire protocol and diagnostics
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): skeleton; client runtime and normalized cache, not usable yet (M11, M12)
-- [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): skeleton; code generator and its CLI, not usable yet (M8, M10)
+- [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; reads typed_graphql.yaml and checks a project's schema and .graphql documents, does not generate code yet (M8, M10)
 - [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): skeleton; typed schema builder, executor and transport handlers, not usable yet (M5 to M7)
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The catalog has the code generator's codes `GQL500`-`GQL506`: configuration
  syntax and content, schema input, anonymous operations, unsupported
  constructs, unknown scalar mappings and no documents (a warning).
```

In `packages/typed_graphql_codegen/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,7 +5,8 @@
 - Package skeleton.
 - `repository` points at the package folder; pub.dev is expected to rewrite
   relative README links from it (to confirm at M16).
-- The README says the package is not usable yet.
+- The README says the package is under construction: it checks a project and
+  does not generate code yet.
 - `CodegenConfig.parse` reads `typed_graphql.yaml` (R7.1) into a
   `ConfigResult`; its problems are `GQL500` (YAML syntax) and `GQL501`.
 - `SchemaLoader.load` reads the schema file (SDL, or an introspection result
@@ -15,3 +16,7 @@
   documents of a project (`GQL503`-`GQL506`); `ClientGenerator.rules` are the
   specified rules without the unused-fragment and lone-anonymous rules, plus
   named operations and no `@defer`/`@stream`.
+- `ProjectFile`: a file of the project, its path and text; the engine reads
+  only given files.
+- The Client Code Generation guide covers the configuration keys, checking a
+  project and the codes `GQL500`-`GQL506`; the `codegen` dartdoc category.
```

In `packages/typed_graphql_codegen/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,15 +4,20 @@
 ![Role](https://img.shields.io/badge/role-codegen-blue)
 ![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)
 
-**The typed_graphql code generator and its CLI: Dart client code from .graphql operations and SDL-first server code, without the analyzer.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
+**Check a GraphQL project for Dart client code generation: read `typed_graphql.yaml`, load the schema and validate the `.graphql` operations, with every problem reported at its file, line and column.** No code is generated yet. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
-> **Status: skeleton.** The package exists so the workspace, CI and the
-> code rules cover it from the start. Its code arrives in stages M8 and M10 of the
-> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.
+> **Status: under construction.** This release reads the project's
+> configuration, `typed_graphql.yaml` (`CodegenConfig`), and checks a project:
+> `ClientGenerator.check` loads the schema, parses and validates the
+> `.graphql` documents as one fragment graph, and reports every problem with
+> its file, line and column. It does not generate code yet; client generation
+> arrives in M10 and the SDL-first server generator in M8 (see the
+> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
-**Not usable yet.** This package exports nothing; the part of typed_graphql that works today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql).
-
-Planned: the client generator and its CLI (M10), then the SDL-first server generator (M8). It does not depend on `analyzer`.
+It does not depend on `analyzer`. The
+[Client Code Generation guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/doc/client_codegen.md)
+lists the configuration keys, shows a check and lists the codes `GQL500` to
+`GQL506`.
 
 ## License
 
```

Create `packages/typed_graphql_codegen/doc/client_codegen.md`:

````markdown
# Client Code Generation

`typed_graphql_codegen` turns a GraphQL schema and the `.graphql` operations
of a Dart project into typed client code. This version checks a project: it
reads the configuration file, loads the schema, parses and validates every
document as one fragment graph, and reports each problem as a diagnostic at
`file:line:column`. It does not write code yet; generation arrives with the
next part of the stage. Bad input never throws: a problem is a diagnostic
with a stable code, in a sealed result or a list.

## Configuration

The project is described by `typed_graphql.yaml`, read by
`CodegenConfig.parse`. Every path is relative to the file's folder and uses
`/` as separator. A key that is not listed, a mistyped value or a malformed
path is a `GQL501`; text that is not YAML is a `GQL500`.

| Key | Default | Meaning |
|---|---|---|
| `schema` | required | The schema: a file (SDL, or an introspection result when the path ends with `.json`) or an `http` or `https` URL. |
| `documents` | `lib/**.graphql` | A glob or a list of globs of the operation documents. |
| `schema_types` | `lib/schema.graphql.dart` | The generated file of the schema's types; the path ends with `.dart`. |
| `persisted_operations` | none | The persisted operations manifest; the path ends with `.json`. Nothing is written when it is missing. |
| `scalars` | none | The custom scalars: each name maps to a `type` and a `codec`. |
| `headers` | none | The HTTP headers of the introspection request. Allowed only when `schema` is a URL. |

A custom scalar is mapped to the Dart type of its values and to the codec
that reads and writes it, a class with a `const` constructor that implements
`ScalarCodec` of that type. Both are written as `<library>#<Name>`, such as
`package:my_app/codecs.dart#MomentCodec`. The `type` of a `dart:core` type
may be its bare name, such as `DateTime`; a `codec` always names its
library. The scalars and the headers are kept sorted by name.

```text
schema: https://example.com/graphql
documents:
  - lib/**.graphql
  - test/**.graphql
schema_types: lib/schema.graphql.dart
persisted_operations: lib/operations.json
scalars:
  Moment:
    type: DateTime
    codec: package:my_app/codecs.dart#MomentCodec
headers:
  Authorization: Bearer token
```

The values of `headers` are kept as written: the configuration reader does
not expand `${NAME}`.

## Checking a project

`CodegenConfig.parse` returns a `ConfigSuccess` or a `ConfigFailure` with the
problems. `ClientGenerator(config).check` takes the schema file and the
document files, each a `ProjectFile` with its path and text, and returns
every diagnostic in report order. The files are given, not read, so the
engine itself touches no file system.

The documents are validated with the specified rules, except that a fragment
nobody spreads is not an error; every operation must be named (`GQL503`). The
fragments of all the files form one graph, so a document may spread a
fragment that another file declares:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main() {
  final result = CodegenConfig.parse('''
schema: schema.graphql
documents: queries/**.graphql
scalars:
  Moment:
    type: DateTime
    codec: package:my_app/codecs.dart#MomentCodec
''', path: 'typed_graphql.yaml');
  if (result is! ConfigSuccess) {
    throw StateError('the configuration is valid');
  }
  final diagnostics = ClientGenerator(result.config).check(
    schema: const ProjectFile('schema.graphql', '''
type Query {
  user: User
}

type User {
  name: String
  joined: Moment
}

scalar Moment
'''),
    documents: const [
      ProjectFile('queries/user.graphql', 'query User { user { ...Name } }'),
      ProjectFile('queries/name.graphql', 'fragment Name on User { nam }'),
    ],
  );
  for (final diagnostic in diagnostics) {
    print(diagnostic);
  }
}
```

It prints:

```text
queries/name.graphql:1:25: error GQL205: Cannot query field "nam" on type "User". Did you mean "name"?
```

A project with no error is ready to generate; a warning does not stop it.

## Diagnostics

The codes of the code generator are the range `GQL5xx`. Ids are public API
and are never reused.

| Code | Severity | Reported when |
|---|---|---|
| `GQL500` | error | `typed_graphql.yaml` is not valid YAML. |
| `GQL501` | error | A configuration key is missing, unknown or mistyped, or a path or Dart reference is malformed. |
| `GQL502` | error | The schema file is not JSON, or is JSON that is not an object, when it should be an introspection result. |
| `GQL503` | error | An operation has no name; the generated classes are named after the operation. |
| `GQL504` | error | A document uses `@defer`, `@stream`, or a fragment on an abstract type at the root of a subscription, which the generator does not support yet. |
| `GQL505` | error | The configuration maps a scalar that the schema does not declare as a custom scalar: it is unknown, is not a scalar, or is built in. |
| `GQL506` | warning | No document matches `documents`. |

The problems of the schema and of the documents keep the codes of the core:
the schema's `GQL1xx` and the operation rules' `GQL2xx`.
````

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc/category_tags_test.dart test/doc/guide_links_test.dart test/doc/guide_snippets_test.dart)
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
git add README.md llms.txt packages/typed_graphql/CHANGELOG.md packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/README.md packages/typed_graphql_codegen/dartdoc_options.yaml packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/test/doc/category_tags_test.dart packages/typed_graphql_codegen/test/doc/guide_links_test.dart packages/typed_graphql_codegen/test/doc/guide_snippets_test.dart
git commit -q -m "docs(typed_graphql_codegen): add the Client Code Generation guide" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Address the M10a review

Fixes the 16 findings of the M10a review (`.superpowers/m10a-fixup.md`): an empty or comment-only document adds nothing (detected with the core lexer, not a message); the premature subscription-root clause of the `GQL504` doc comment and guide row is dropped; `dart:core#Name` must name a known core type; URL schemes are matched case-insensitively and any other scheme is `GQL501`; header names must be RFC 7230 tokens and values free of control characters; a JSON reader failure names the schema file; `ProjectSourceMap` clamps both ends of a span; the joined project text is still parsed again (the core parser cannot start at an offset), with a true comment and a test that a file ending in a body-less extension followed by a file starting with `{` is reported, not crashed; configuration defaults are shared; the loader no longer imports the generator; built-in scalar names come from `BuiltIns` and reports are ordered by mapping name; `schema: .` and an empty base name are `GQL501`; and the missing tests.

Commit on the branch: `cf86ad5`.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`, `packages/typed_graphql_codegen/lib/src/config/codegen_config.dart`, `packages/typed_graphql_codegen/lib/src/config/config_draft.dart`, `packages/typed_graphql_codegen/lib/src/config/config_reader.dart`, `packages/typed_graphql_codegen/lib/src/config/dart_reference_reader.dart`, `packages/typed_graphql_codegen/lib/src/config/header_reader.dart`, `packages/typed_graphql_codegen/lib/src/config/relative_path.dart`, `packages/typed_graphql_codegen/lib/src/config/schema_location_reader.dart`, `packages/typed_graphql_codegen/lib/src/documents/project_documents.dart`, `packages/typed_graphql_codegen/lib/src/documents/project_source_map.dart`, `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, `packages/typed_graphql_codegen/lib/src/generator/client_project_loader.dart`, `packages/typed_graphql_codegen/lib/src/generator/scalar_mapping_checker.dart`, `packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart`, `packages/typed_graphql_codegen/lib/src/schema/schema_loader.dart`
- Test: `packages/typed_graphql_codegen/test/config/codegen_config_test.dart`, `packages/typed_graphql_codegen/test/config/scalar_config_test.dart`, `packages/typed_graphql_codegen/test/documents/project_documents_test.dart`, `packages/typed_graphql_codegen/test/documents/project_source_map_test.dart`, `packages/typed_graphql_codegen/test/generator/client_generator_test.dart`, `packages/typed_graphql_codegen/test/schema/schema_loader_test.dart`

**Interfaces:**
- Consumes: Tasks 1-6.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// config/config_reader.dart
  ConfigResult read()

// generator/client_project_loader.dart
final class const ClientProjectLoader(…)
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/config/codegen_config_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -275,4 +275,91 @@ scalars:
       ]);
     });
   });
+
+  group('review fixes', () {
+    test('dart:core accepts only a core type', () {
+      expect(
+        problems(
+          'schema: s.graphql\n'
+          'scalars:\n'
+          '  A:\n'
+          '    type: dart:core#Nope\n'
+          '    codec: package:a/a.dart#C\n',
+        ),
+        [
+          "$_path:4:11: error GQL501: 'type' must be "
+              "'<library>#<Name>', such as 'package:my_app/codecs.dart#MyType'.",
+        ],
+      );
+    });
+
+    test('an upper-case HTTPS scheme is a URL', () {
+      expect(read('schema: HTTPS://x/graphql\n').schema, isA<SchemaUrl>());
+    });
+
+    test('another scheme is not a path', () {
+      expect(problems('schema: ftp://x\n'), [
+        "$_path:1:9: error GQL501: 'schema' must be a relative path.",
+      ]);
+    });
+
+    test('a one-letter scheme is not a path', () {
+      expect(problems('schema: c:/s.graphql\n'), [
+        "$_path:1:9: error GQL501: 'schema' must be a relative path.",
+      ]);
+    });
+
+    test('a header value with a control character', () {
+      expect(
+        problems('schema: https://h.dev/g\nheaders:\n  A: "x\\ny"\n'),
+        [
+          "$_path:3:6: error GQL501: The value of header 'A' must not have a "
+              'control character.',
+        ],
+      );
+    });
+
+    test('a header name that is not an HTTP token', () {
+      expect(problems('schema: https://h.dev/g\nheaders:\n  "A(b)": c\n'), [
+        "$_path:3:3: error GQL501: 'A(b)' is not a valid header name.",
+      ]);
+    });
+
+    test('a schema without a file name', () {
+      expect(problems('schema: .\n'), [
+        "$_path:1:9: error GQL501: 'schema' must name a file.",
+      ]);
+    });
+
+    test('schema_types without a base name', () {
+      expect(problems('schema: s.graphql\nschema_types: .dart\n'), [
+        "$_path:2:15: error GQL501: 'schema_types' must have a file name "
+            "before '.dart'.",
+      ]);
+    });
+
+    test('a YAML alias value is a string error, not a throw', () {
+      expect(problems('schema: s.graphql\nx: &a 1\nschema_types: *a\n'), [
+        "$_path:2:1: error GQL501: Unknown key 'x'; the keys are "
+            "'documents', 'headers', 'persisted_operations', 'scalars', "
+            "'schema', 'schema_types'.",
+        "$_path:2:4: error GQL501: 'schema_types' must be a string.",
+      ]);
+    });
+
+    test('a non-string key is reported, not thrown', () {
+      expect(problems('schema: s.graphql\n1: a\n'), [
+        "$_path:2:1: error GQL501: Unknown key '1'; the keys are "
+            "'documents', 'headers', 'persisted_operations', 'scalars', "
+            "'schema', 'schema_types'.",
+      ]);
+    });
+
+    test('a .. segment inside a documents glob', () {
+      expect(problems('schema: s.graphql\ndocuments: lib/../x/**.graphql\n'), [
+        "$_path:2:12: error GQL501: 'documents' must not have a '..' "
+            'segment.',
+      ]);
+    });
+  });
 }
```

In `packages/typed_graphql_codegen/test/config/scalar_config_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -67,7 +67,7 @@ void main() {
     });
 
     test('a codec in dart:core has no library', () {
-      expect(problems(scalar('    type: Uri\n    codec: dart:core#Codec\n')), [
+      expect(problems(scalar('    type: Uri\n    codec: dart:core#String\n')), [
         "$_path:5:12: error GQL501: 'codec' must name a library.",
       ]);
     });
```

In `packages/typed_graphql_codegen/test/documents/project_documents_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -116,4 +116,34 @@ void main() {
   test('no files give an empty document', () {
     expect(read(const []).document.definitions, isEmpty);
   });
+
+  test('an empty file and a comment-only file add no definition', () {
+    final documents = read(const [
+      ProjectFile('0.graphql', ''),
+      fileA,
+      ProjectFile('c.graphql', '# nothing here\n'),
+      ProjectFile('d.graphql', '\uFEFF , \n'),
+    ]);
+    expect(documents.document.definitions, hasLength(1));
+  });
+
+  test('only empty files give an empty document', () {
+    final documents = read(const [
+      ProjectFile('a.graphql', ''),
+      ProjectFile('b.graphql', '# c'),
+    ]);
+    expect(documents.document.definitions, isEmpty);
+  });
+
+  test('a join that fails although each file parses is reported', () {
+    expect(
+      problems(const [
+        ProjectFile('a.graphql', 'extend enum E @d'),
+        ProjectFile('b.graphql', '{ user { name } }'),
+      ]),
+      [
+        'b.graphql:1:8: error GQL007: Expected Name, found "{".',
+      ],
+    );
+  });
 }
```

In `packages/typed_graphql_codegen/test/documents/project_source_map_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -79,4 +79,19 @@ void main() {
     );
     expect(map.translateDiagnostic(diagnostic), diagnostic);
   });
+
+  test('a span at the end of the text is clamped into the last file', () {
+    final span = map.translate(SourceSpan(map.source, 13, 13));
+    expect(['$span', span.start, span.end], ['c.graphql:1:3', 2, 2]);
+  });
+
+  test('a span at the first offset of a later file starts there', () {
+    final span = map.translate(SourceSpan(map.source, 4, 6));
+    expect(['$span', span.text], ['b.graphql:1:1', 'de']);
+  });
+
+  test('a span on the joining line break is empty at the file end', () {
+    final span = map.translate(SourceSpan(map.source, 3, 4));
+    expect(['$span', span.start, span.end], ['a.graphql:1:4', 3, 3]);
+  });
 }
```

In `packages/typed_graphql_codegen/test/generator/client_generator_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -137,7 +137,7 @@ void main() {
       );
     });
 
-    test('an operation name used in two files is reported in both', () {
+    test('an operation name used in two files is reported once, relating the other file', () {
       expect(
         check(const [
           ProjectFile('a.graphql', 'query A { hello }\n'),
@@ -250,4 +250,59 @@ scalars:
       );
     });
   });
+
+  group('more inputs', () {
+    test('empty and comment-only files next to a valid one are accepted', () {
+      expect(
+        check(const [
+          ProjectFile('0.graphql', ''),
+          _aFile,
+          _bFile,
+          ProjectFile('z.graphql', '# only a comment\n'),
+        ]),
+        isEmpty,
+      );
+    });
+
+    test('a project of only empty files has no documents', () {
+      expect(check(const [ProjectFile('a.graphql', '')]), [
+        "warning GQL506: No document matches the configuration's "
+            "'documents'.",
+      ]);
+    });
+
+    test('a schema failure hides an unmapped custom scalar', () {
+      // The mapping is checked against a schema, so only the schema's own
+      // problem is reported.
+      expect(
+        check(
+          const [_aFile, _bFile],
+          schema: const ProjectFile('schema.graphql', 'type Query {\n'),
+          config:
+              'schema: schema.graphql\nscalars:\n  Foo:\n    type: DateTime\n'
+              '    codec: package:a/a.dart#C\n',
+        ),
+        ['schema.graphql:2:1: error GQL007: Expected Name, found <EOF>.'],
+      );
+    });
+
+    test('a JSON schema is read as an introspection result', () {
+      final document = const Parser()
+          .parse(Source(_schema.text))
+          .requireDocument();
+      final built = const SchemaBuilder().fromSdl(document) as BuildSuccess;
+      final json = ProjectFile(
+        'schema.json',
+        built.schema.toIntrospection().toString(),
+      );
+      expect(
+        check(
+          const [_aFile, _bFile],
+          schema: json,
+          config: 'schema: schema.json\n',
+        ),
+        isEmpty,
+      );
+    });
+  });
 }
```

In `packages/typed_graphql_codegen/test/schema/schema_loader_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -81,7 +81,10 @@ void main() {
       expect(messages, hasLength(1));
       expect(
         messages.single,
-        startsWith('x.json:1:1: error GQL502: The schema file is not JSON: '),
+        startsWith(
+          r'x.json:1:1: error GQL502: The schema file cannot be read: $: '
+          'not JSON: ',
+        ),
       );
     });
 
@@ -97,4 +100,18 @@ void main() {
       expect(messages.single, startsWith('x.json:1:1: error GQL15'));
     });
   });
+
+  test(
+    'a JSON nested past the depth limit is reported with the depth limit',
+    () {
+      final text = '${'[' * 2000}${']' * 2000}';
+      final messages = problems('x.json', text);
+      expect(messages, hasLength(1));
+      expect(
+        messages.single,
+        r'x.json:1:1: error GQL502: The schema file cannot be read: $: arrays '
+        'and objects are nested deeper than 512.',
+      );
+    },
+  );
 }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/config/codegen_config_test.dart test/config/scalar_config_test.dart test/documents/project_documents_test.dart test/documents/project_source_map_test.dart test/generator/client_generator_test.dart test/schema/schema_loader_test.dart)
```

Expected: FAIL. The new and changed tests fail on the behaviour this task fixes (assertion failures; a test that uses a name the next step adds does not compile).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -527,9 +527,8 @@ enum DiagnosticCode(
   /// reads; its classes are named after the operation.
   anonymousOperation('GQL503'),
 
-  /// `GQL504`: a construct the code generator does not support yet: `@defer`,
-  /// `@stream`, or a fragment on an abstract type spread at the root of a
-  /// subscription.
+  /// `GQL504`: a construct the code generator does not support yet: `@defer`
+  /// or `@stream`.
   unsupportedInDocument('GQL504'),
 
   /// `GQL505`: the configuration maps a scalar the schema does not have as a
```

In `packages/typed_graphql_codegen/lib/src/config/codegen_config.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -13,20 +13,26 @@ final class CodegenConfig {
   /// file's missing key has.
   const CodegenConfig({
     required this.schema,
-    this.documents = const ['lib/**.graphql'],
-    this.schemaTypes = 'lib/schema.graphql.dart',
+    this.documents = defaultDocuments,
+    this.schemaTypes = defaultSchemaTypes,
     this.persistedOperations,
     this.scalars = const {},
     this.headers = const {},
   });
 
+  /// The `documents` of a file without that key.
+  static const List<String> defaultDocuments = ['lib/**.graphql'];
+
+  /// The `schema_types` of a file without that key.
+  static const String defaultSchemaTypes = 'lib/schema.graphql.dart';
+
   /// Reads the text of the configuration file at [path].
   ///
   /// Bad input never throws: a YAML syntax error is one `GQL500`, every other
   /// problem a `GQL501`, all in a [ConfigFailure]. [path] only names the file
   /// in the diagnostics.
   static ConfigResult parse(String text, {required String path}) =>
-      ConfigReader(Source(text, name: path)).read(text);
+      ConfigReader(Source(text, name: path)).read();
 
   /// Where the schema is: a file or an endpoint.
   final SchemaLocation schema;
```

In `packages/typed_graphql_codegen/lib/src/config/config_draft.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,10 +11,10 @@ final class ConfigDraft {
   SchemaLocation? schema;
 
   /// The `documents` globs.
-  List<String> documents = const ['lib/**.graphql'];
+  List<String> documents = CodegenConfig.defaultDocuments;
 
   /// The `schema_types` path.
-  String schemaTypes = 'lib/schema.graphql.dart';
+  String schemaTypes = CodegenConfig.defaultSchemaTypes;
 
   /// The `persisted_operations` path, if any.
   String? persistedOperations;
```

In `packages/typed_graphql_codegen/lib/src/config/config_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -28,8 +28,9 @@ final class ConfigReader(
     'schema_types',
   ];
 
-  /// Reads [text], the body of [source].
-  ConfigResult read(String text) {
+  /// Reads the body of [source].
+  ConfigResult read() {
+    final text = source.body;
     final YamlNode root;
     try {
       root = loadYamlNode(text);
@@ -133,7 +134,12 @@ final class ConfigReader(
   ) {
     final path = const RelativePath().read(node, label, report);
     if (path == null) return null;
-    if (path.endsWith(suffix)) return path;
+    final name = path.substring(path.lastIndexOf('/') + 1);
+    if (name == suffix) {
+      report.error(node, "'$label' must have a file name before '$suffix'.");
+      return null;
+    }
+    if (name.endsWith(suffix)) return path;
     report.error(node, "'$label' must end with '$suffix'.");
     return null;
   }
```

In `packages/typed_graphql_codegen/lib/src/config/dart_reference_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -43,7 +43,10 @@ final class const DartReferenceReader() {
     }
     final library = text.substring(0, hash);
     final name = text.substring(hash + 1);
-    if (!_library.hasMatch(library) || !_identifier.hasMatch(name)) {
+    final isCoreName = library != 'dart:core' || _coreTypes.contains(name);
+    if (!_library.hasMatch(library) ||
+        !_identifier.hasMatch(name) ||
+        !isCoreName) {
       report.error(
         node,
         "'$label' must be '<library>#<Name>', such as "
```

In `packages/typed_graphql_codegen/lib/src/config/header_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,7 +7,9 @@ final class const HeaderReader() {
   /// Creates the reader.
   this;
 
-  static final RegExp _name = RegExp(r'^[^\s:]+$');
+  // RFC 7230 token.
+  static final RegExp _name = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
+  static final RegExp _control = RegExp(r'[\x00-\x08\x0A-\x1F\x7F]');
 
   /// Returns the headers of [node], sorted by name; the entries with problems
   /// are left out and reported.
@@ -26,7 +28,15 @@ final class const HeaderReader() {
         continue;
       }
       final text = report.string(value, 'headers.$name');
-      if (text != null) headers[name] = text;
+      if (text == null) continue;
+      if (_control.hasMatch(text)) {
+        report.error(
+          value,
+          "The value of header '$name' must not have a control character.",
+        );
+        continue;
+      }
+      headers[name] = text;
     }
     return {
       for (final name in headers.keys.toList()..sort()) name: headers[name]!,
```

In `packages/typed_graphql_codegen/lib/src/config/relative_path.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,7 +8,9 @@ final class const RelativePath() {
   /// Creates the reader.
   this;
 
-  static final RegExp _driveLetter = RegExp('^[A-Za-z]:');
+  // Any scheme, a one-letter one included: paths are POSIX, so a drive
+  // letter is not a path either.
+  static final RegExp _scheme = RegExp('^[A-Za-z][A-Za-z0-9+.-]*:');
 
   /// Returns the path [node] holds, or reports why it is not one named by
   /// [label] and returns null.
@@ -24,12 +26,18 @@ final class const RelativePath() {
   String? _problemOf(String path) {
     if (path.isEmpty) return 'must not be empty.';
     if (path.contains(r'\')) return "must use '/' as the separator.";
-    if (path.startsWith('/') || _driveLetter.hasMatch(path)) {
+    if (path.startsWith('/') ||
+        path.contains('://') ||
+        _scheme.hasMatch(path)) {
       return 'must be a relative path.';
     }
-    if (path.split('/').contains('..')) {
+    final segments = path.split('/');
+    if (segments.contains('..')) {
       return "must not have a '..' segment.";
     }
+    if (segments.last.isEmpty || segments.last == '.') {
+      return 'must name a file.';
+    }
     return null;
   }
 }
```

In `packages/typed_graphql_codegen/lib/src/config/schema_location_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -14,7 +14,8 @@ final class const SchemaLocationReader() {
   SchemaLocation? read(YamlNode node, ConfigReport report) {
     final text = report.string(node, 'schema');
     if (text == null) return null;
-    if (!text.startsWith('http://') && !text.startsWith('https://')) {
+    final lower = text.toLowerCase();
+    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
       final path = const RelativePath().read(node, 'schema', report);
       return path == null ? null : SchemaFile(path);
     }
```

In `packages/typed_graphql_codegen/lib/src/documents/project_documents.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,7 +8,9 @@ import 'project_source_map.dart';
 /// is visible from every operation (R7.2).
 ///
 /// The document's offsets index [ProjectSourceMap.source]; the map gives the
-/// file of each offset.
+/// file of each offset. A file with no tokens adds nothing. Documents are
+/// parsed with the parser's default limits, except that the token limit is
+/// lifted.
 final class ProjectDocuments(
   /// The files, sorted by path.
   final List<ProjectFile> files,
@@ -39,15 +41,17 @@ final class ProjectDocuments(
       return ProjectDocumentsUnreadable(problems);
     }
     final map = ProjectSourceMap(sorted);
-    if (sorted.isEmpty) {
-      // An empty text is a syntax error, so the empty document is built.
+    if (sorted.every(_isBlank)) {
+      // An empty text is a syntax error (spec §2.2), so the empty document is
+      // built.
       return ProjectDocumentsRead(
         ProjectDocuments(sorted, map, Document(const [])),
       );
     }
-    // Each file parsed alone and ends at a token boundary, and the joining
-    // line break ends a trailing comment, so the whole cannot fail; the
-    // branch is defensive.
+    // Each file parsed alone, but the joined text can still fail: a file
+    // ending in `extend enum E @d` makes the next file's leading `{` the
+    // extension's body. The core parser cannot start at an offset, so the
+    // joined text is parsed again and its problems are translated.
     final whole = const Parser(
       options: ParserOptions(maxTokens: null),
     ).parse(map.source);
@@ -67,6 +71,7 @@ final class ProjectDocuments(
   static List<Diagnostic> _parseEach(List<ProjectFile> sorted) {
     final problems = <Diagnostic>[];
     for (final file in sorted) {
+      if (_isBlank(file)) continue;
       final result = const Parser().parse(Source(file.text, name: file.path));
       if (result is ParseFailure) {
         problems.addAll(result.diagnostics);
@@ -74,4 +79,13 @@ final class ProjectDocuments(
     }
     return problems;
   }
+
+  // Only ignored tokens (whitespace, commas, comments, BOM): the file adds no
+  // definition and is not a syntax error.
+  static bool _isBlank(ProjectFile file) =>
+      Lexer(
+        Source(file.text, name: file.path),
+        DiagnosticSink(),
+      ).advance().kind ==
+      TokenKind.eof;
 }
```

In `packages/typed_graphql_codegen/lib/src/documents/project_source_map.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -64,13 +64,12 @@ final class ProjectSourceMap(List<ProjectFile> files) {
     final index = fileIndexAt(span.start);
     final fileSource = _sources[index];
     final fileStart = _starts[index];
-    final end = span.end - fileStart;
-    return SourceSpan(
-      fileSource,
-      span.start - fileStart,
-      // A span can end on the joining line break, which is not in the file.
-      end > fileSource.body.length ? fileSource.body.length : end,
-    );
+    final length = fileSource.body.length;
+    // A span can start or end on the joining line break, or past the last
+    // file, which are not in the file.
+    final start = (span.start - fileStart).clamp(0, length);
+    final end = (span.end - fileStart).clamp(start, length);
+    return SourceSpan(fileSource, start, end);
   }
 
   /// [diagnostic] with its span and related spans translated by [translate].
```

In `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -56,6 +56,10 @@ final class const ClientGenerator(final CodegenConfig config) {
   /// Checks the schema and the documents as `generate` will read them;
   /// returns every diagnostic, warnings included, in report order.
   ///
+  /// When the schema cannot be loaded, the documents are only parsed: their
+  /// syntax errors come after the schema's, and no validation error is
+  /// reported.
+  ///
   /// [schema] is the schema file and [documents] the files the configuration's
   /// `documents` globs matched; nothing is written.
   List<Diagnostic> check({
@@ -64,6 +68,7 @@ final class const ClientGenerator(final CodegenConfig config) {
   }) {
     final result = ClientProjectLoader(
       config,
+      rules,
     ).load(schema: schema, documents: documents);
     return switch (result) {
       ClientProjectLoaded(:final warnings) => warnings,
```

In `packages/typed_graphql_codegen/lib/src/generator/client_project_loader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,15 +6,17 @@ import '../documents/project_documents_result.dart';
 import '../project/project_file.dart';
 import '../schema/schema_load_result.dart';
 import '../schema/schema_loader.dart';
-import 'client_generator.dart';
 import 'client_project.dart';
 import 'client_project_result.dart';
 import 'scalar_mapping_checker.dart';
 
 /// Reads the schema and the documents of a project and validates them with
-/// [ClientGenerator.rules]; shared by `check` and `generate`.
-final class const ClientProjectLoader(final CodegenConfig config) {
-  /// Creates a loader for [config].
+/// `rules` (`ClientGenerator.rules`); shared by `check` and `generate`.
+final class const ClientProjectLoader(
+  final CodegenConfig config,
+  final List<ValidationRule> rules,
+) {
+  /// Creates a loader for [config] that validates documents with [rules].
   this;
 
   /// Loads the project; never throws for bad input.
@@ -23,26 +25,30 @@ final class const ClientProjectLoader(final CodegenConfig config) {
     required List<ProjectFile> documents,
   }) {
     final read = ProjectDocuments.read(documents);
-    final loaded = const SchemaLoader().load(schema);
-    if (loaded is! SchemaLoaded) {
+    return switch (const SchemaLoader().load(schema)) {
       // The documents are read anyway so that one run shows every syntax
       // error.
-      return ClientProjectFailed([
-        if (loaded is SchemaNotLoaded) ...loaded.diagnostics,
-        if (read is ProjectDocumentsUnreadable) ...read.diagnostics,
-      ]);
-    }
-    final mapping = const ScalarMappingChecker().check(
-      config,
-      loaded.schema.schema,
-    );
+      SchemaNotLoaded(:final diagnostics) => ClientProjectFailed([
+        ...diagnostics,
+        if (read case ProjectDocumentsUnreadable(diagnostics: final more))
+          ...more,
+      ]),
+      SchemaLoaded(schema: final valid) => _withSchema(valid, read),
+    };
+  }
+
+  ClientProjectResult _withSchema(
+    ValidSchema schema,
+    ProjectDocumentsResult read,
+  ) {
+    final mapping = const ScalarMappingChecker().check(config, schema.schema);
     return switch (read) {
       ProjectDocumentsUnreadable(:final diagnostics) => ClientProjectFailed([
         ...mapping,
         ...diagnostics,
       ]),
       ProjectDocumentsRead(documents: final files) => _validate(
-        loaded.schema,
+        schema,
         files,
         mapping,
       ),
@@ -55,7 +61,7 @@ final class const ClientProjectLoader(final CodegenConfig config) {
     List<Diagnostic> mapping,
   ) {
     final warnings = <Diagnostic>[
-      if (documents.files.isEmpty)
+      if (documents.document.definitions.isEmpty)
         Diagnostic(
           .noDocuments,
           .warning,
@@ -63,7 +69,7 @@ final class const ClientProjectLoader(final CodegenConfig config) {
         ),
     ];
     final map = documents.sourceMap;
-    final result = const DocumentValidator(rules: ClientGenerator.rules)
+    final result = DocumentValidator(rules: rules)
         .validate(schema, documents.document, source: map.source);
     return switch (result) {
       InvalidDocument(:final diagnostics) => ClientProjectFailed([
```

In `packages/typed_graphql_codegen/lib/src/generator/scalar_mapping_checker.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,12 +8,12 @@ final class const ScalarMappingChecker() {
   /// Creates the checker.
   this;
 
-  static const _builtIn = {'Int', 'Float', 'String', 'Boolean', 'ID'};
-
   /// The problems of [config]'s mappings against [schema], in name order.
   List<Diagnostic> check(CodegenConfig config, Schema schema) {
     final problems = <Diagnostic>[];
-    for (final MapEntry(:key, :value) in config.scalars.entries) {
+    final names = config.scalars.keys.toList()..sort();
+    for (final key in names) {
+      final value = config.scalars[key]!;
       final message = _problemWith(key, schema);
       if (message != null) {
         problems.add(
@@ -25,7 +25,7 @@ final class const ScalarMappingChecker() {
   }
 
   String? _problemWith(String name, Schema schema) {
-    if (_builtIn.contains(name)) {
+    if (const BuiltIns().scalarNamed(name) != null) {
       return "The built-in scalar '$name' cannot be mapped.";
     }
     return switch (schema.typeNamed(name)) {
```

In `packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -10,11 +10,8 @@ final class const IntrospectionFileReader() {
   BuildResult read(String text, Source source) {
     final place = SourceSpan(source, 0, 0);
     return switch (const JsonReader().parse(text)) {
-      DecodeFailure(:final message, :final path) => _failure(
-        path.isEmpty
-            ? 'The schema file is $message.'
-            : 'The schema file is not valid JSON: '
-                  '${DecodeFailure(message, path: path)}.',
+      final DecodeFailure failure => _failure(
+        'The schema file cannot be read: $failure.',
         place,
       ),
       DecodeSuccess(value: final JsonObject object) => _build(object, place),
```

In `packages/typed_graphql_codegen/lib/src/schema/schema_loader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../config/schema_location.dart';
 import '../project/project_file.dart';
 import 'introspection_file_reader.dart';
 import 'schema_load_result.dart';
@@ -15,7 +16,7 @@ final class const SchemaLoader() {
   /// Builds and validates the schema [file] holds; never throws.
   SchemaLoadResult load(ProjectFile file) {
     final source = Source(file.text, name: file.path);
-    final built = file.path.endsWith('.json')
+    final built = SchemaFile(file.path).isIntrospection
         ? const IntrospectionFileReader().read(file.text, source)
         : _fromSdl(source);
     return switch (built) {
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/config/codegen_config_test.dart test/config/scalar_config_test.dart test/documents/project_documents_test.dart test/documents/project_source_map_test.dart test/generator/client_generator_test.dart test/schema/schema_loader_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- A `.graphql` file with no tokens adds nothing instead of failing the project; stricter checks of `schema`, paths and `headers` (all `GQL501`).
```

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -121,7 +121,7 @@ and are never reused.
 | `GQL501` | error | A configuration key is missing, unknown or mistyped, or a path or Dart reference is malformed. |
 | `GQL502` | error | The schema file is not JSON, or is JSON that is not an object, when it should be an introspection result. |
 | `GQL503` | error | An operation has no name; the generated classes are named after the operation. |
-| `GQL504` | error | A document uses `@defer`, `@stream`, or a fragment on an abstract type at the root of a subscription, which the generator does not support yet. |
+| `GQL504` | error | A document uses `@defer` or `@stream`, which the generator does not support yet. |
 | `GQL505` | error | The configuration maps a scalar that the schema does not declare as a custom scalar: it is unknown, is not a scalar, or is built in. |
 | `GQL506` | warning | No document matches `documents`. |
 
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/lib/src/config/codegen_config.dart packages/typed_graphql_codegen/lib/src/config/config_draft.dart packages/typed_graphql_codegen/lib/src/config/config_reader.dart packages/typed_graphql_codegen/lib/src/config/dart_reference_reader.dart packages/typed_graphql_codegen/lib/src/config/header_reader.dart packages/typed_graphql_codegen/lib/src/config/relative_path.dart packages/typed_graphql_codegen/lib/src/config/schema_location_reader.dart packages/typed_graphql_codegen/lib/src/documents/project_documents.dart packages/typed_graphql_codegen/lib/src/documents/project_source_map.dart packages/typed_graphql_codegen/lib/src/generator/client_generator.dart packages/typed_graphql_codegen/lib/src/generator/client_project_loader.dart packages/typed_graphql_codegen/lib/src/generator/scalar_mapping_checker.dart packages/typed_graphql_codegen/lib/src/schema/introspection_file_reader.dart packages/typed_graphql_codegen/lib/src/schema/schema_loader.dart packages/typed_graphql_codegen/test/config/codegen_config_test.dart packages/typed_graphql_codegen/test/config/scalar_config_test.dart packages/typed_graphql_codegen/test/documents/project_documents_test.dart packages/typed_graphql_codegen/test/documents/project_source_map_test.dart packages/typed_graphql_codegen/test/generator/client_generator_test.dart packages/typed_graphql_codegen/test/schema/schema_loader_test.dart
git commit -q -m "fix(typed_graphql_codegen): address the M10a review" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

From `.superpowers/m10-open-questions.md` and the spec's section 17, with the choice this plan makes:

- Question 6 (environment in headers): `${NAME}` only in header values, kept as written by the engine and expanded by the CLI (M10d); values are never printed.
- Question 7 (numbering): this plan adds `GQL500`-`GQL506` with their final ids (`GQL505` unknownScalarMapping, `GQL506` noDocuments as a warning); the spec draft's table numbered them differently and is now corrected.

## Self-review

- Spec coverage: section 3 (Tasks 1, 7), section 4 (Tasks 2, 7), section 5 (Tasks 3, 5, 7), the codes of section 9 (Tasks 1, 2, 4), section 10 (Tasks 1-3, 7), section 13 (Task 6).
- Every code block in this plan is the content of a commit that passed the green check; no placeholder remains.
- Type consistency: each task's Produces block is extracted from its commit, and later tasks consume those names.

## After the plan

M10b (`2026-10-15-m10b-runtime-and-schema-types.md`) follows on the same branch. The handoff is updated by M10d.
