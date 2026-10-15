# M10b Runtime Contract and Schema Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Optional<T>` in the core (R4.4, R7.7); the generated-code contract in `typed_graphql_client` (`GraphQLOperation`, `OperationDocument`, the `DataCodec` kinds, `DataContext`, `DataEquality`, `DataFormatException`); the emitter base (`DartWriter`, `DartStringLiteral`, `DartNames`, `Imports`, `GeneratedHeader`); type mapping and enums (R7.6), input objects with `@oneOf` (R7.7), scalar mapping (R7.8); the name checks `GQL507` and `GQL508`; `ClientGenerator.generate` with the schema-types library, the golden harness and the analysis test (R7.10); and the fixes of the M10b review.

**Architecture:** `ClientGenerator.generate` returns a `GenerationResult` (diagnostics and `GeneratedFile`s; an error means no files). `SchemaTypeUsage` finds the enums and input objects the documents reach (transitively through input objects); `GeneratedNames` registers every declared name and member and reports collisions (`GQL507`) and names that hide a `dart:core` type the code uses (`GQL508`) before any file is written. `SchemaTypesEmitter` writes the library through `EnumEmitter` (a sealed class, a `…Known` enum, an `…Unknown` class), `RegularInputEmitter` and `OneOfInputEmitter` (a sealed class with one variant per field), over `TypeMapper` (GraphQL type to `DartType` and codec expression, without recursion) and `DartWriter`. Each generated class declares its own private codecs. Generated code imports the core as `graphql` and the client as `client`.

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, null-aware elements, patterns, sealed classes, records), `package:test`, `package:meta`; in the codegen package `yaml`, `crypto`, `path`, and in its command line `args`, `glob` and `dart:io`. No `analyzer`, no `dart_style`, no `package:gql`.

**Spec:** `docs/superpowers/specs/2026-10-15-m10-client-codegen-design.md` (sections 2, 7, 8, 9, 11, 16), `docs/requirements.md` R7.6-R7.8, R7.10, R0.2.

**Base:** the M10a plan (`2026-10-15-m10a-codegen-front-end.md`) applied on `main` at `57f85e8`. Task 1 was committed before the last M10a task on the branch (disjoint files). M10c (`2026-10-15-m10c-operations-and-fragments.md`) follows.

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

1. Schema descriptions are untrusted text in doc comments: a code fence, an unclosed fence or a whitespace-only line must not break the comment or the next one (Task 5, `input_object_emitter_test.dart` "a deprecated field and a described type with a code fence"; Task 9, `dart_writer_test.dart` "doc forgets an unclosed fence of the previous comment").
2. String and name escaping: every literal the emitter writes (`$`, quotes, backslashes, control characters, lone surrogates) is a valid Dart literal of the same text (Task 3, `dart_string_literal_test.dart` "literal of ${value.codeUnits}"); a `$` in an enum's unknown-class name (Task 4, `enum_emitter_test.dart` "the unknown class escapes a dollar in its name"); a field named `client` or `graphql` does not shadow an import prefix (Task 9, `dart_names_test.dart` "memberName escapes the import prefixes of the generated code").
3. Deep wrapped types map without recursion (Task 4, `type_mapper_test.dart` "a list nested 200 levels deep maps").
4. Names that would make the output not compile are diagnostics and no file is written: Task 7, `client_generator_generate_test.dart` "a name collision is an error and writes nothing", `generated_names_test.dart` "a reserved name is a GQL508 at its declaration"; Task 9, "enum values with one Dart name are a GQL507", "input fields with one Dart name are a GQL507 at the field".
5. The runtime codecs never throw on any JSON kind (Task 2, `object_codecs_test.dart` "$name never throws for any kind of JSON"); a present `null` differs from absent (Task 1, `optional_test.dart` "a present null differs from absent").

## File map

| File | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql/lib/src/protocol/optional.dart` | A value that may be absent, as an argument, input field or variable that was not given, which GraphQL tells apart from an explicit `null` (September2025 §6.4.1 "Coercing Variable Values" and the "Input Object" input coercion | 1 |
| `packages/typed_graphql/test/protocol/optional_test.dart` | Tests | 1 |
| `packages/typed_graphql_client/dartdoc_options.yaml` | Package file | 2 |
| `packages/typed_graphql_client/doc/operations.md` | Document | 2 |
| `packages/typed_graphql_client/lib/src/operation/data_codec.dart` | Reads one kind of value of a response from JSON and writes it back | 2 |
| `packages/typed_graphql_client/lib/src/operation/data_context.dart` | What a generated reader needs besides the JSON | 2 |
| `packages/typed_graphql_client/lib/src/operation/data_enum.dart` | A value of a generated enum | 2 |
| `packages/typed_graphql_client/lib/src/operation/data_equality.dart` | Equality of the values of generated classes | 2 |
| `packages/typed_graphql_client/lib/src/operation/data_format_exception.dart` | A value of a response that does not have the shape the generated code expects, and where it is | 2 |
| `packages/typed_graphql_client/lib/src/operation/data_object.dart` | A generated class that writes itself as JSON | 2 |
| `packages/typed_graphql_client/lib/src/operation/enum_data_codec.dart` | Reads and writes a generated enum by its GraphQL name (R7.6) | 2 |
| `packages/typed_graphql_client/lib/src/operation/graphql_operation.dart` | A generated operation with its variables | 2 |
| `packages/typed_graphql_client/lib/src/operation/json_data_codec.dart` | Keeps a custom scalar the configuration does not map as its JSON (R7.8 | 2 |
| `packages/typed_graphql_client/lib/src/operation/list_data_codec.dart` | Reads and writes a list whose items [item] reads | 2 |
| `packages/typed_graphql_client/lib/src/operation/nullable_data_codec.dart` | Reads and writes a nullable value | 2 |
| `packages/typed_graphql_client/lib/src/operation/object_data_codec.dart` | Reads and writes a generated class | 2 |
| `packages/typed_graphql_client/lib/src/operation/operation_document.dart` | The document of a generated operation as it is sent (R7.9) | 2 |
| `packages/typed_graphql_client/lib/src/operation/scalar_data_codec.dart` | Reads and writes a scalar through its [ScalarCodec] | 2 |
| `packages/typed_graphql_client/test/doc/category_tags_test.dart` | Tests | 2 |
| `packages/typed_graphql_client/test/doc/guide_links_test.dart` | Tests | 2 |
| `packages/typed_graphql_client/test/doc/guide_snippets_test.dart` | Tests | 2 |
| `packages/typed_graphql_client/test/operation/object_codecs_test.dart` | Tests | 2 |
| `packages/typed_graphql_client/test/operation/support_types_test.dart` | Tests | 2 |
| `packages/typed_graphql_client/test/operation/wrapper_codecs_test.dart` | Tests | 2 |
| `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart` | Turns GraphQL names into Dart identifiers | 3 |
| `packages/typed_graphql_codegen/lib/src/emit/dart_string_literal.dart` | Writes a Dart string literal that satisfies `prefer_single_quotes` and `use_raw_strings` | 3 |
| `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart` | A text builder for generated Dart code | 3 |
| `packages/typed_graphql_codegen/lib/src/emit/generated_header.dart` | Writes the header every generated file starts with | 3 |
| `packages/typed_graphql_codegen/lib/src/emit/imports.dart` | Collects the imports of one generated library and writes them in `directives_ordering` order | 3 |
| `packages/typed_graphql_codegen/test/emit/dart_names_test.dart` | Tests | 3 |
| `packages/typed_graphql_codegen/test/emit/dart_string_literal_test.dart` | Tests | 3 |
| `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart` | Tests | 3 |
| `packages/typed_graphql_codegen/test/emit/generated_header_test.dart` | Tests | 3 |
| `packages/typed_graphql_codegen/test/emit/imports_test.dart` | Tests | 3 |
| `packages/typed_graphql_codegen/lib/src/emit/dart_type.dart` | A Dart type as written in generated code, with the codec that reads and writes its values | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/enum_emitter.dart` | Writes the Dart declarations of a GraphQL enum (spec §7 "Enums") | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/type_mapper.dart` | Maps GraphQL types to the Dart types of generated code and their codecs (spec §7 "Scalars", R7.6, R7.8) | 4 |
| `packages/typed_graphql_codegen/test/emit/enum_emitter_test.dart` | Tests | 4 |
| `packages/typed_graphql_codegen/test/emit/type_mapper_test.dart` | Tests | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/input_field.dart` | The plan of one input field, or one operation variable | 5 |
| `packages/typed_graphql_codegen/lib/src/emit/input_object_emitter.dart` | Writes the Dart class of a GraphQL input object (spec §7 "Input objects and variables", R7.7) | 5 |
| `packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart` | Writes the classes of a `@oneOf` input object | 5 |
| `packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart` | Writes the class of an input object that is not `@oneOf` | 5 |
| `packages/typed_graphql_codegen/test/emit/input_field_test.dart` | Tests | 5 |
| `packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart` | Tests | 5 |
| `packages/typed_graphql_codegen/dart_test.yaml` | Package file | 7 |
| `packages/typed_graphql_codegen/lib/src/emit/schema_types_emitter.dart` | Writes the schema-types library | 7 |
| `packages/typed_graphql_codegen/lib/src/generator/generated_file.dart` | A file the generator writes | 7 |
| `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart` | The top-level names one generation declares, with what declared each, so that two declarations with one name, or a name that hides a Dart type the generated code uses, are diagnostics instead of broken code | 7 |
| `packages/typed_graphql_codegen/lib/src/generator/generation_result.dart` | What `ClientGenerator.generate` produced | 7 |
| `packages/typed_graphql_codegen/lib/src/generator/schema_type_usage.dart` | Finds the schema types the documents use, which are the only ones generated (spec §7, "pruned") | 7 |
| `packages/typed_graphql_codegen/test/generated_code_test.dart` | Tests | 7 |
| `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart` | Tests | 7 |
| `packages/typed_graphql_codegen/test/generator/generated_names_test.dart` | Tests | 7 |
| `packages/typed_graphql_codegen/test/generator/schema_type_usage_test.dart` | Tests | 7 |
| `packages/typed_graphql_codegen/test/golden_test.dart` | Tests | 7 |
| `packages/typed_graphql_codegen/test/support/generated_package.dart` | A temporary Dart package that holds a golden case's generated code, so that the analyzer and the VM check it | 7 |
| `packages/typed_graphql_codegen/test/support/golden_case.dart` | One directory of `test/goldens/` | 7 |
| `packages/typed_graphql_codegen/test/goldens/no_documents/` | Golden case (3 new files) | 7 |
| `packages/typed_graphql_codegen/test/goldens/schema_types/` | Golden case (7 new files) | 7 |
| `packages/typed_graphql/CHANGELOG.md` | Modified | 1, 6 |
| `packages/typed_graphql/doc/protocol.md` | Modified | 1 |
| `packages/typed_graphql/lib/typed_graphql.dart` | Modified | 1 |
| `llms.txt` | Modified | 2 |
| `packages/typed_graphql_client/CHANGELOG.md` | Modified | 2 |
| `packages/typed_graphql_client/README.md` | Modified | 2 |
| `packages/typed_graphql_client/lib/typed_graphql_client.dart` | Modified | 2 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modified | 6 |
| `packages/typed_graphql_codegen/CHANGELOG.md` | Modified | 7, 8 |
| `packages/typed_graphql_codegen/README.md` | Modified | 7, 8 |
| `packages/typed_graphql_codegen/doc/client_codegen.md` | Modified | 7, 8 |
| `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart` | Modified | 7 |
| `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart` | Modified | 7, 9 |

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

### Task 1: Add Optional for values that may be absent

`Optional<T>` is a sealed family (`Present`, `Absent`) that tells an argument, input field or variable that was not given from an explicit `null` (R4.4, R7.7). It lives in the core's `protocol/` because the server (M5) and the generated client code share it (open question 1); the Protocol guide gains its section.

Commit on the branch: `b7299f1`.

**Files:**
- Create: `packages/typed_graphql/lib/src/protocol/optional.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/doc/protocol.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/protocol/optional_test.dart`

**Interfaces:**
- Consumes: The core `protocol/` layer.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// protocol/optional.dart
sealed class Optional<T>
  const factory Optional.present(T value) = Present<T>
  const factory Optional.absent() = Absent<T>
final class const Present<T>(…)
  int get hashCode
  String toString()
final class const Absent<T>() implements Optional<T>
  int get hashCode
  String toString()
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/protocol/optional_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  test('a present value equals a present equal value', () {
    expect(
      const Optional<String>.present('a'),
      equals(const Optional<String>.present('a')),
    );
  });

  test('a present value equals one with another static type', () {
    expect(
      const Optional<int?>.present(1),
      equals(const Optional<Object?>.present(1)),
    );
  });

  test('a present value differs from one with another value', () {
    expect(
      const Optional<int>.present(1),
      isNot(equals(const Optional<int>.present(2))),
    );
  });

  test('a present null differs from absent', () {
    expect(
      const Optional<String?>.present(null),
      isNot(equals(const Optional<String?>.absent())),
    );
  });

  test('absent values are equal across types', () {
    expect(
      const Optional<int>.absent(),
      equals(const Optional<String?>.absent()),
    );
  });

  test('hash codes agree with equality', () {
    expect(
      const Optional<int?>.present(1).hashCode,
      const Optional<Object?>.present(1).hashCode,
    );
    expect(
      const Optional<int>.absent().hashCode,
      const Optional<String>.absent().hashCode,
    );
  });

  test('toString names the state', () {
    expect(
      [
        const Optional<String?>.present('a').toString(),
        const Optional<String?>.present(null).toString(),
        const Optional<String?>.absent().toString(),
      ],
      ['Optional.present(a)', 'Optional.present(null)', 'Optional.absent()'],
    );
  });

  test('a switch with two cases is exhaustive', () {
    String describe(Optional<int> value) => switch (value) {
      Present(:final value) => 'present $value',
      Absent() => 'absent',
    };
    expect(describe(const Optional.present(3)), 'present 3');
    expect(describe(const Optional.absent()), 'absent');
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/protocol/optional_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/protocol/optional.dart`:

````dart
/// A value that may be absent, as an argument, input field or variable that
/// was not given, which GraphQL tells apart from an explicit `null`
/// (September2025 §6.4.1 "Coercing Variable Values" and the "Input Object"
/// input coercion; R4.4, R7.7).
///
/// ```dart
/// const name = Optional.present('Ada');
/// const none = Optional<String?>.absent();
/// ```
///
/// {@category protocol}
sealed class Optional<T> {
  /// A present [value], which may be `null` when [T] is nullable.
  const factory Optional.present(T value) = Present<T>;

  /// No value.
  const factory Optional.absent() = Absent<T>;
}

/// A present value of an [Optional].
///
/// {@category protocol}
final class const Present<T>(
  /// The value, `null` included when [T] is nullable.
  final T value,
) implements Optional<T> {
  /// Creates a present [value].
  this;

  @override
  bool operator ==(Object other) =>
      other is Present<Object?> && other.value == value;

  @override
  int get hashCode => Object.hash(Present, value);

  @override
  String toString() => 'Optional.present($value)';
}

/// The absence of a value in an [Optional].
///
/// {@category protocol}
final class const Absent<T>() implements Optional<T> {
  /// Creates the absence of a value.
  this;

  @override
  bool operator ==(Object other) => other is Absent<Object?>;

  @override
  int get hashCode => (Absent).hashCode;

  @override
  String toString() => 'Optional.absent()';
}
````

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -61,6 +61,7 @@ export 'src/protocol/graphql_error.dart';
 export 'src/protocol/graphql_request.dart';
 export 'src/protocol/json_reader.dart';
 export 'src/protocol/json_value.dart';
+export 'src/protocol/optional.dart';
 export 'src/protocol/path_segment.dart';
 export 'src/protocol/response_payload.dart';
 export 'src/schema/build/build_result.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/protocol/optional_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -13,6 +13,8 @@
 - `GraphQLError`: the error format of the spec, read and written.
 - `GraphQLRequest` and `ResponsePayload` (`ExecutionResult`,
   `RequestErrorResult`).
+- `Optional`, `Present` and `Absent`: a value that may be absent, which
+  GraphQL tells apart from `null`.
 - The syntax tree: `Node` (`children`, `withChildren`, `isEquivalentTo`),
   `Name`, `Document`, and the `Value` and `TypeRef` families.
 - Executable nodes: `OperationDefinition`, `FragmentDefinition`, the
```

In `packages/typed_graphql/doc/protocol.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -277,3 +277,39 @@ data: {"hero":{"name":"R2-D2","friends":[null,null]}}
 first error at [hero, friends, 1, name]
 DecodeSuccess(RequestErrorResult({"errors":[{"message":"Syntax Error: Unexpected \")\"."}]}))
 ```
+
+## Optional values
+
+GraphQL tells an argument, input field or variable that was not given from one
+given as `null`. `Optional<T>` holds that difference: `Optional.present(value)`
+(the value may be `null` when `T` is nullable) or `Optional.absent()`. A
+`switch` over it needs two cases.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+void describe(Optional<String?> value) {
+  switch (value) {
+    case Present(value: final text?):
+      print('present: $text');
+    case Present():
+      print('present null');
+    case Absent():
+      print('absent');
+  }
+}
+
+void main() {
+  describe(const Optional.present('Ada'));
+  describe(const Optional.present(null));
+  describe(const Optional.absent());
+}
+```
+
+It prints:
+
+```text
+present: Ada
+present null
+absent
+```
````

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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/doc/protocol.md packages/typed_graphql/lib/src/protocol/optional.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/protocol/optional_test.dart
git commit -q -m "feat(typed_graphql): add Optional for values that may be absent" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Add the contract generated code compiles against

`typed_graphql_client` gains `lib/src/operation/` (spec section 8): `GraphQLOperation` with `GraphQLQuery`, `GraphQLMutation` and `GraphQLSubscription`, the const `OperationDocument`, the `DataCodec` kinds generated code composes (scalar, enum, object, nullable, list, JSON) with `DataContext`, `DataEquality`, `DataObject`, `DataEnum` and the internal `DataFormatException`, which never leaves a public decode (R0.3). The Generated Operations guide and the package's documentation suite come with it.

Commit on the branch: `317240d`.

**Files:**
- Create: `packages/typed_graphql_client/dartdoc_options.yaml`, `packages/typed_graphql_client/doc/operations.md`, `packages/typed_graphql_client/lib/src/operation/data_codec.dart`, `packages/typed_graphql_client/lib/src/operation/data_context.dart`, `packages/typed_graphql_client/lib/src/operation/data_enum.dart`, `packages/typed_graphql_client/lib/src/operation/data_equality.dart`, `packages/typed_graphql_client/lib/src/operation/data_format_exception.dart`, `packages/typed_graphql_client/lib/src/operation/data_object.dart`, `packages/typed_graphql_client/lib/src/operation/enum_data_codec.dart`, `packages/typed_graphql_client/lib/src/operation/graphql_operation.dart`, `packages/typed_graphql_client/lib/src/operation/json_data_codec.dart`, `packages/typed_graphql_client/lib/src/operation/list_data_codec.dart`, `packages/typed_graphql_client/lib/src/operation/nullable_data_codec.dart`, `packages/typed_graphql_client/lib/src/operation/object_data_codec.dart`, `packages/typed_graphql_client/lib/src/operation/operation_document.dart`, `packages/typed_graphql_client/lib/src/operation/scalar_data_codec.dart`
- Modify: `llms.txt`, `packages/typed_graphql_client/CHANGELOG.md`, `packages/typed_graphql_client/README.md`, `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Test: `packages/typed_graphql_client/test/doc/category_tags_test.dart`, `packages/typed_graphql_client/test/doc/guide_links_test.dart`, `packages/typed_graphql_client/test/doc/guide_snippets_test.dart`, `packages/typed_graphql_client/test/operation/object_codecs_test.dart`, `packages/typed_graphql_client/test/operation/support_types_test.dart`, `packages/typed_graphql_client/test/operation/wrapper_codecs_test.dart`

**Interfaces:**
- Consumes: The core: `JsonValue`, `DecodeResult`, `ScalarCodec`, `GraphQLRequest`, `OperationType`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// operation/data_codec.dart
abstract base class DataCodec<T>
  const DataCodec()
  T read(JsonValue json, DataContext context)
  JsonValue write(T value)
  T field(JsonObject object, String key, DataContext context)
  Optional<T> optionalField(
  DecodeResult<T> decode(

// operation/data_context.dart
final class const DataContext([
  bool flag(String name)

// operation/data_enum.dart
abstract interface class DataEnum
  String get raw

// operation/data_equality.dart
final class const DataEquality()
  bool equals(Object? a, Object? b)
  int hash(Object? value)

// operation/data_format_exception.dart
final class DataFormatException implements Exception
  const DataFormatException(this.message, [this.path = const []])
  final String message
  final List<PathSegment> path
  DataFormatException inside(PathSegment segment)
  String toString()

// operation/data_object.dart
abstract interface class DataObject
  JsonObject toJson()

// operation/enum_data_codec.dart
final class const EnumDataCodec<T extends DataEnum>(…)
  final T Function(String raw) parse,
  T read(JsonValue json, DataContext context)
  JsonValue write(T value)

// operation/graphql_operation.dart
sealed class GraphQLOperation<D extends Object>
  const GraphQLOperation()
  OperationDocument get document
  JsonObject get variablesJson
  DecodeResult<D> decodeData(JsonObject data)
  GraphQLRequest toRequest()
abstract base class GraphQLQuery<D extends Object> extends GraphQLOperation<D>
  const GraphQLQuery()
abstract base class GraphQLMutation<D extends Object>
  const GraphQLMutation()
abstract base class GraphQLSubscription<D extends Object>
  const GraphQLSubscription()

// operation/json_data_codec.dart
final class const JsonDataCodec() extends DataCodec<JsonValue>
  JsonValue read(JsonValue json, DataContext context)
  JsonValue write(JsonValue value)

// operation/list_data_codec.dart
final class const ListDataCodec<T>(…)
  List<T> read(JsonValue json, DataContext context)
  JsonValue write(List<T> value)

// operation/nullable_data_codec.dart
final class const NullableDataCodec<T extends Object>(…)
  T? read(JsonValue json, DataContext context)
  JsonValue write(T? value)

// operation/object_data_codec.dart
final class const ObjectDataCodec<T extends DataObject>(…)
  final T Function(JsonObject json, DataContext context) reader,
  T read(JsonValue json, DataContext context)
  JsonValue write(T value)

// operation/operation_document.dart
final class const OperationDocument

// operation/scalar_data_codec.dart
final class const ScalarDataCodec<T>(…)
  T read(JsonValue json, DataContext context)
  JsonValue write(T value)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_client/test/doc/category_tags_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../typed_graphql/test/doc/public_type.dart';

/// Every exported type is in the `operations` dartdoc category, which
/// `dartdoc_options.yaml` declares with its guide (R11.2).
void main() {
  final barrel = File('lib/typed_graphql_client.dart').readAsStringSync();
  final exported = [
    for (final match in RegExp("export '([^']+)';").allMatches(barrel))
      match[1]!,
  ];
  final options = File('dartdoc_options.yaml').readAsStringSync();

  test('the only category declared is operations', () {
    final declared = [
      for (final match in RegExp(
        r'^ {4}([a-z-]+):$',
        multiLine: true,
      ).allMatches(options))
        match[1]!,
    ];
    expect(declared, ['operations']);
  });

  test('the category has its guide', () {
    expect(options, contains('markdown: doc/operations.md'));
    expect(File('doc/operations.md').existsSync(), isTrue);
  });

  group('exported types', () {
    for (final path in exported) {
      test(path, () {
        final source = File('lib/$path').readAsStringSync();
        final untagged = [
          for (final type in const PublicTypes().declaredIn(source))
            if (type.countOf('{@category operations}') != 1) type.name,
        ];
        expect(
          untagged,
          isEmpty,
          reason: 'give each exactly one {@category operations} in its doc',
        );
      });
    }
  });
}
```

Create `packages/typed_graphql_client/test/doc/guide_links_test.dart`:

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

Create `packages/typed_graphql_client/test/doc/guide_snippets_test.dart`:

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

Create `packages/typed_graphql_client/test/operation/object_codecs_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

sealed class Color implements DataEnum {
  const Color();

  factory Color.parse(String raw) => switch (raw) {
    'RED' => const KnownColor.red(),
    _ => UnknownColor(raw),
  };
}

final class KnownColor extends Color {
  const KnownColor.red();

  @override
  String get raw => 'RED';
}

final class UnknownColor extends Color {
  const UnknownColor(this.raw);

  @override
  final String raw;
}

final class Person implements DataObject {
  Person._(JsonObject json, DataContext context)
    : name = const ScalarDataCodec(StringCodec()).field(json, 'name', context),
      nickname = const NullableDataCodec(
        ScalarDataCodec(StringCodec()),
      ).field(json, 'nickname', context),
      middle = const NullableDataCodec(
        ScalarDataCodec(StringCodec()),
      ).optionalField(json, 'middle', context);

  static const codec = ObjectDataCodec(Person._);

  final String name;
  final String? nickname;
  final Optional<String?> middle;

  @override
  JsonObject toJson() => JsonObject({'name': JsonString(name)});
}

void main() {
  group('EnumDataCodec', () {
    const codec = EnumDataCodec(Color.parse);

    test('reads a known value', () {
      expect(
        (codec.decode(const JsonString('RED')) as DecodeSuccess<Color>).value,
        isA<KnownColor>(),
      );
    });

    test('reads an unknown value, keeping its name', () {
      final value = (codec.decode(
        const JsonString('BLUE'),
      ) as DecodeSuccess<Color>).value;
      expect(value.raw, 'BLUE');
      expect(value, isA<UnknownColor>());
    });

    test('reports a value that is not a string', () {
      expect(codec.decode(const JsonNull()), isA<DecodeFailure>());
    });

    test('writes the name', () {
      expect(codec.write(const UnknownColor('BLUE')), const JsonString('BLUE'));
    });
  });

  group('ObjectDataCodec', () {
    JsonObject json(Map<String, JsonValue> fields) => JsonObject(fields);

    Person read(JsonObject object) =>
        (Person.codec.decode(object) as DecodeSuccess<Person>).value;

    test('reads the members', () {
      final person = read(json({'name': const JsonString('Ada')}));
      expect(person.name, 'Ada');
    });

    test('writes through toJson', () {
      final person = read(json({'name': const JsonString('Ada')}));
      expect(
        Person.codec.write(person),
        json({'name': const JsonString('Ada')}),
      );
    });

    test('reports a value that is not an object', () {
      expect(Person.codec.decode(const JsonNull()), isA<DecodeFailure>());
    });

    test('reports a bad member at its key', () {
      final result = Person.codec.decode(json({'name': JsonNumber(1)}));
      expect((result as DecodeFailure).path, [const PathKey('name')]);
    });

    test('reads a missing member as null', () {
      final person = read(json({'name': const JsonString('Ada')}));
      expect(person.nickname, isNull);
    });

    test('reads the optional field of a missing member as absent', () {
      final person = read(json({'name': const JsonString('Ada')}));
      expect(person.middle, const Optional<String?>.absent());
    });

    test('reads the optional field of null as present null', () {
      final person = read(
        json({'name': const JsonString('Ada'), 'middle': const JsonNull()}),
      );
      expect(person.middle, const Optional<String?>.present(null));
    });
  });

  group('decode', () {
    final kinds = <JsonValue>[
      const JsonNull(),
      const JsonBool(true),
      JsonNumber(1),
      const JsonString('x'),
      JsonArray(const []),
      JsonObject(const {}),
    ];
    final codecs = <String, DataCodec<Object?>>{
      'scalar': const ScalarDataCodec(StringCodec()),
      'nullable': const NullableDataCodec(ScalarDataCodec(StringCodec())),
      'list': const ListDataCodec(ScalarDataCodec(StringCodec())),
      'enum': const EnumDataCodec(Color.parse),
      'object': Person.codec,
      'json': const JsonDataCodec(),
    };

    for (final MapEntry(key: name, value: codec) in codecs.entries) {
      test('$name never throws for any kind of JSON', () {
        for (final kind in kinds) {
          expect(() => codec.decode(kind), returnsNormally);
        }
      });
    }
  });
}
```

Create `packages/typed_graphql_client/test/operation/support_types_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class _Ping extends GraphQLQuery<String> {
  const _Ping();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Ping',
    type: OperationType.query,
    text: 'query Ping{ping}',
    sha256: 'abc',
  );

  @override
  JsonObject get variablesJson => JsonObject({'id': const JsonString('1')});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const ScalarDataCodec(StringCodec()).decode(data['ping']!);
}

void main() {
  group('DataContext.flag', () {
    test('is the value that was sent', () {
      final context = DataContext(JsonObject({'on': const JsonBool(true)}));
      expect(context.flag('on'), isTrue);
    });

    test('is the default when the variable was not sent', () {
      final context = DataContext(JsonObject(const {}), const {'on': true});
      expect(context.flag('on'), isTrue);
    });

    test('is false when there is no value and no default', () {
      expect(DataContext(JsonObject(const {})).flag('on'), isFalse);
    });

    test('is the default when the value is not a Boolean', () {
      final context = DataContext(
        JsonObject({'on': const JsonString('yes')}),
        const {'on': true},
      );
      expect(context.flag('on'), isTrue);
    });

    test('is the default when there are no variables', () {
      expect(const DataContext(null, {'on': true}).flag('on'), isTrue);
    });
  });

  group('DataEquality', () {
    const equality = DataEquality();
    final a = [
      [1, 2],
      [3],
    ];
    final b = [
      [1, 2],
      [3],
    ];
    final first = [1];
    final second = [1];

    test('compares nested lists item by item', () {
      expect(equality.equals(a, b), isTrue);
    });

    test('tells nested lists with different items apart', () {
      expect(
        equality.equals(a, [
          [1, 2],
          [4],
        ]),
        isFalse,
      );
    });

    test('hashes equal nested lists alike', () {
      expect(equality.hash(a), equality.hash(b));
    });

    test('compares present optionals of equal lists as equal', () {
      expect(
        equality.equals(Optional.present(first), Optional.present(second)),
        isTrue,
      );
    });

    test('hashes equal present optionals alike', () {
      expect(
        equality.hash(Optional.present(first)),
        equality.hash(Optional.present(second)),
      );
    });

    test('tells present from absent', () {
      expect(
        equality.equals(
          const Optional<List<int>>.absent(),
          Optional.present(first),
        ),
        isFalse,
      );
    });

    test('compares absent with absent', () {
      expect(
        equality.equals(
          const Optional<int>.absent(),
          const Optional<int>.absent(),
        ),
        isTrue,
      );
    });

    test('hashes absent optionals alike', () {
      expect(
        equality.hash(const Optional<int>.absent()),
        equality.hash(const Optional<int>.absent()),
      );
    });
  });

  group('DataFormatException', () {
    test('inside prepends a segment to the path', () {
      final exception = const DataFormatException('bad', [
        PathIndex(1),
      ]).inside(const PathKey('items'));
      expect(exception.path, [const PathKey('items'), const PathIndex(1)]);
    });

    test('inside keeps the message', () {
      expect(
        const DataFormatException('bad').inside(const PathIndex(0)).message,
        'bad',
      );
    });
  });

  group('GraphQLOperation', () {
    final request = const _Ping().toRequest();

    test('toRequest sends the document text', () {
      expect(request.query, 'query Ping{ping}');
    });

    test('toRequest sends the operation name', () {
      expect(request.operationName, 'Ping');
    });

    test('toRequest sends the variables', () {
      expect(request.variables, JsonObject({'id': const JsonString('1')}));
    });

    test('is exhaustive over its three kinds', () {
      const GraphQLOperation<Object> operation = _Ping();
      final kind = switch (operation) {
        GraphQLQuery() => 'query',
        GraphQLMutation() => 'mutation',
        GraphQLSubscription() => 'subscription',
      };
      expect(kind, 'query');
    });
  });
}
```

Create `packages/typed_graphql_client/test/operation/wrapper_codecs_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  const scalar = ScalarDataCodec(StringCodec());

  group('ScalarDataCodec', () {
    test('reads a value through its codec', () {
      expect(scalar.decode(const JsonString('a')), const DecodeSuccess('a'));
    });

    test('writes a value through its codec', () {
      expect(scalar.write('a'), const JsonString('a'));
    });

    test('reports a wrong value with the codec message and an empty path', () {
      final expected = const StringCodec().decode(JsonNumber(1));
      expect(expected, isA<DecodeFailure>());
      final result = scalar.decode(JsonNumber(1));
      expect(result, isA<DecodeFailure>());
      expect(
        (result as DecodeFailure).message,
        (expected as DecodeFailure).message,
      );
      expect(result.path, isEmpty);
    });
  });

  group('NullableDataCodec', () {
    const codec = NullableDataCodec(scalar);

    test('reads null', () {
      expect(
        codec.decode(const JsonNull()),
        const DecodeSuccess<String?>(null),
      );
    });

    test('reads a value', () {
      expect(
        codec.decode(const JsonString('a')),
        const DecodeSuccess<String?>('a'),
      );
    });

    test('writes null as JSON null', () {
      expect(codec.write(null), const JsonNull());
    });

    test('writes a value', () {
      expect(codec.write('a'), const JsonString('a'));
    });
  });

  group('ListDataCodec', () {
    const codec = ListDataCodec(scalar);

    test('reads the items', () {
      final result = codec.decode(
        JsonArray(const [JsonString('a'), JsonString('b')]),
      );
      expect((result as DecodeSuccess<List<String>>).value, ['a', 'b']);
    });

    test('reads an unmodifiable list', () {
      final result = codec.decode(JsonArray(const [JsonString('a')]));
      final list = (result as DecodeSuccess<List<String>>).value;
      expect(() => list.add('b'), throwsUnsupportedError);
    });

    test('reports a bad item at its index', () {
      final result = codec.decode(
        JsonArray([
          const JsonString('a'),
          const JsonString('b'),
          JsonNumber(1),
        ]),
      );
      expect((result as DecodeFailure).path, [const PathIndex(2)]);
    });

    test('reports a bad item of a nested list at both indexes', () {
      const nested = ListDataCodec(codec);
      final result = nested.decode(
        JsonArray([
          JsonArray(const [JsonString('a')]),
          JsonArray([JsonNumber(1)]),
        ]),
      );
      expect((result as DecodeFailure).path, [
        const PathIndex(1),
        const PathIndex(0),
      ]);
    });

    test('reports a value that is not a list with an empty path', () {
      final result = codec.decode(const JsonString('a'));
      expect((result as DecodeFailure).path, isEmpty);
    });

    test('writes the items', () {
      expect(
        codec.write(['a', 'b']),
        JsonArray(const [JsonString('a'), JsonString('b')]),
      );
    });
  });

  group('JsonDataCodec', () {
    test('keeps any JSON', () {
      final json = JsonObject({
        'a': JsonArray([JsonNumber(1)]),
      });
      expect(
        const JsonDataCodec().decode(json),
        DecodeSuccess<JsonValue>(json),
      );
    });

    test('writes the JSON as it is', () {
      expect(const JsonDataCodec().write(const JsonNull()), const JsonNull());
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 600 dart test test/doc/category_tags_test.dart test/doc/guide_links_test.dart test/doc/guide_snippets_test.dart test/operation/object_codecs_test.dart test/operation/support_types_test.dart test/operation/wrapper_codecs_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Update the package files**

Create `packages/typed_graphql_client/dartdoc_options.yaml`:

```yaml
dartdoc:
  categories:
    operations:
      markdown: doc/operations.md
      displayName: Generated Operations
  categoryOrder:
    - operations
  showUndocumentedCategories: true
```

- [ ] **Step 4: Write the implementation**

Create `packages/typed_graphql_client/lib/src/operation/data_codec.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'data_context.dart';
import 'data_format_exception.dart';

/// Reads one kind of value of a response from JSON and writes it back: the
/// building block of generated data classes (R7.3).
///
/// Generated code composes the kinds as constants, such as
/// `ListDataCodec(NullableDataCodec(UserCard.codec))` for `[UserCard]`.
/// [read] throws a [DataFormatException] for a value of the wrong shape;
/// [decode] turns it into a [DecodeFailure] with the path, so bad input
/// never escapes as an exception (R0.3).
///
/// {@category operations}
abstract base class DataCodec<T> {
  /// Creates a codec.
  const DataCodec();

  /// Reads [json]; throws a [DataFormatException] when it has the wrong
  /// shape.
  T read(JsonValue json, DataContext context);

  /// Writes [value] as the JSON [read] reads back.
  JsonValue write(T value);

  /// Reads the member [key] of [object]; a missing member reads as `null`,
  /// as a field skipped by `@skip` or `@include`.
  T field(JsonObject object, String key, DataContext context) {
    try {
      return read(object[key] ?? const JsonNull(), context);
    } on DataFormatException catch (exception) {
      throw exception.inside(PathKey(key));
    }
  }

  /// Reads the member [key] of [object], absent when [object] has no such
  /// member (input objects, R7.7).
  Optional<T> optionalField(
    JsonObject object,
    String key,
    DataContext context,
  ) => switch (object[key]) {
    null => const Optional.absent(),
    _ => Optional.present(field(object, key, context)),
  };

  /// Reads [json] and returns the value, or the problem and its path.
  DecodeResult<T> decode(
    JsonValue json, [
    DataContext context = const DataContext(),
  ]) {
    try {
      return DecodeSuccess(read(json, context));
    } on DataFormatException catch (exception) {
      return DecodeFailure(exception.message, path: exception.path);
    }
  }
}
```

Create `packages/typed_graphql_client/lib/src/operation/data_context.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// What a generated reader needs besides the JSON: the operation's
/// variables, which decide whether a fragment spread under `@include` or
/// `@skip` was selected.
///
/// {@category operations}
final class const DataContext([
  /// The variables the operation was sent with; null when there were none.
  final JsonObject? variables,

  /// The defaults of the operation's Boolean variables, by name, for the
  /// variables that were not sent.
  final Map<String, bool> defaults = const {},
]) {
  /// Creates the context of an operation sent with [variables].
  this;

  /// The value of the Boolean variable [name]: as sent, else its default,
  /// else false (validation lets only a variable that is non-null or has a
  /// default stand in `@include(if:)` and `@skip(if:)`).
  bool flag(String name) => switch (variables?[name]) {
    JsonBool(:final value) => value,
    _ => defaults[name] ?? false,
  };
}
```

Create `packages/typed_graphql_client/lib/src/operation/data_enum.dart`:

```dart
/// A value of a generated enum: a known value or an unknown one, both with
/// the GraphQL name (R7.6).
///
/// {@category operations}
abstract interface class DataEnum {
  /// The value's name in GraphQL, such as `ADMIN`.
  String get raw;
}
```

Create `packages/typed_graphql_client/lib/src/operation/data_equality.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Equality of the values of generated classes: lists item by item and
/// present [Optional]s by their values, at any depth (R7.3: equal data
/// compares equal, so a cache update that yields equal data rebuilds
/// nothing).
///
/// Generated `==` and `hashCode` use it for every member whose type holds a
/// list; other members compare with `==`.
///
/// {@category operations}
final class const DataEquality() {
  /// Creates the equality.
  this;

  /// Whether [a] and [b] are equal: lists item by item, present optionals
  /// by their values, anything else with `==`.
  bool equals(Object? a, Object? b) => switch ((a, b)) {
    (final List<Object?> a, final List<Object?> b) => _equalLists(a, b),
    (Present(value: final Object? a), Present(value: final Object? b)) =>
      equals(a, b),
    _ => a == b,
  };

  bool _equalLists(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!equals(a[index], b[index])) return false;
    }
    return true;
  }

  /// A hash code of [value] consistent with [equals].
  int hash(Object? value) => switch (value) {
    final List<Object?> items => Object.hashAll(items.map(hash)),
    Present(value: final Object? present) => Object.hash(
      Present,
      hash(present),
    ),
    _ => value.hashCode,
  };
}
```

Create `packages/typed_graphql_client/lib/src/operation/data_format_exception.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// A value of a response that does not have the shape the generated code
/// expects, and where it is.
///
/// Generated readers throw it; [DataCodec.decode] catches it and returns a
/// [DecodeFailure] with the same message and path, so it never leaves a
/// public `decode` (R0.3). Code outside generated libraries has no reason to
/// throw or catch it.
///
/// {@category operations}
final class DataFormatException implements Exception {
  /// Creates the exception for [message] at [path] (empty: the value being
  /// read).
  const DataFormatException(this.message, [this.path = const []]);

  /// What is wrong, as a sentence.
  final String message;

  /// Where the value is, from the value [DataCodec.decode] was given.
  final List<PathSegment> path;

  /// The same problem one level deeper: inside [segment] of its parent.
  DataFormatException inside(PathSegment segment) =>
      DataFormatException(message, [segment, ...path]);

  @override
  String toString() => 'DataFormatException: $message';
}
```

Create `packages/typed_graphql_client/lib/src/operation/data_object.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// A generated class that writes itself as JSON: data, fragments, input
/// objects and variables.
///
/// {@category operations}
abstract interface class DataObject {
  /// The JSON of this value; for data, the response JSON it was read from,
  /// up to member order and the `__typename` the generator added.
  JsonObject toJson();
}
```

Create `packages/typed_graphql_client/lib/src/operation/enum_data_codec.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';
import 'data_enum.dart';
import 'data_format_exception.dart';

/// Reads and writes a generated enum by its GraphQL name (R7.6).
///
/// {@category operations}
final class const EnumDataCodec<T extends DataEnum>(
  /// The enum's `parse` constructor: the known value of a name, or the
  /// unknown value that keeps it.
  final T Function(String raw) parse,
) extends DataCodec<T> {
  /// Creates the codec of the enum [parse] reads.
  this;

  @override
  T read(JsonValue json, DataContext context) => switch (json) {
    JsonString(:final value) => parse(value),
    _ => throw DataFormatException('Expected an enum value name, got $json.'),
  };

  @override
  JsonValue write(T value) => JsonString(value.raw);
}
```

Create `packages/typed_graphql_client/lib/src/operation/graphql_operation.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'operation_document.dart';

/// A generated operation with its variables: what a client sends and how it
/// reads the data back (R7.9).
///
/// The three kinds let a client accept only queries where only queries make
/// sense (R8.1).
///
/// {@category operations}
sealed class GraphQLOperation<D extends Object> {
  /// Creates an operation.
  const GraphQLOperation();

  /// The document sent for this operation.
  OperationDocument get document;

  /// The variables as JSON, with only the values that were given.
  JsonObject get variablesJson;

  /// Reads the `data` member of a response to this operation.
  DecodeResult<D> decodeData(JsonObject data);

  /// The request for this operation over HTTP or a socket.
  GraphQLRequest toRequest() => GraphQLRequest(
    query: document.text,
    operationName: document.name,
    variables: variablesJson,
  );
}

/// A generated query.
///
/// {@category operations}
abstract base class GraphQLQuery<D extends Object> extends GraphQLOperation<D> {
  /// Creates a query.
  const GraphQLQuery();
}

/// A generated mutation.
///
/// {@category operations}
abstract base class GraphQLMutation<D extends Object>
    extends GraphQLOperation<D> {
  /// Creates a mutation.
  const GraphQLMutation();
}

/// A generated subscription.
///
/// {@category operations}
abstract base class GraphQLSubscription<D extends Object>
    extends GraphQLOperation<D> {
  /// Creates a subscription.
  const GraphQLSubscription();
}
```

Create `packages/typed_graphql_client/lib/src/operation/json_data_codec.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';

/// Keeps a custom scalar the configuration does not map as its JSON (R7.8:
/// an unmapped custom scalar is a [JsonValue], never `dynamic`).
///
/// {@category operations}
final class const JsonDataCodec() extends DataCodec<JsonValue> {
  /// Creates the codec.
  this;

  @override
  JsonValue read(JsonValue json, DataContext context) => json;

  @override
  JsonValue write(JsonValue value) => value;
}
```

Create `packages/typed_graphql_client/lib/src/operation/list_data_codec.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';
import 'data_format_exception.dart';

/// Reads and writes a list whose items [item] reads; the list read is
/// unmodifiable.
///
/// {@category operations}
final class const ListDataCodec<T>(
  /// The codec of the items.
  final DataCodec<T> item,
) extends DataCodec<List<T>> {
  /// Creates the list form of [item].
  this;

  @override
  List<T> read(JsonValue json, DataContext context) => switch (json) {
    JsonArray(:final items) => List.unmodifiable([
      for (var index = 0; index < items.length; index++)
        _item(items[index], index, context),
    ]),
    _ => throw DataFormatException('Expected a list, got $json.'),
  };

  T _item(JsonValue json, int index, DataContext context) {
    try {
      return item.read(json, context);
    } on DataFormatException catch (exception) {
      throw exception.inside(PathIndex(index));
    }
  }

  @override
  JsonValue write(List<T> value) =>
      JsonArray([for (final element in value) item.write(element)]);
}
```

Create `packages/typed_graphql_client/lib/src/operation/nullable_data_codec.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';

/// Reads and writes a nullable value: JSON `null` is `null`, anything else
/// goes to [item].
///
/// {@category operations}
final class const NullableDataCodec<T extends Object>(
  /// The codec of the non-null values.
  final DataCodec<T> item,
) extends DataCodec<T?> {
  /// Creates the nullable form of [item].
  this;

  @override
  T? read(JsonValue json, DataContext context) => switch (json) {
    JsonNull() => null,
    _ => item.read(json, context),
  };

  @override
  JsonValue write(T? value) => switch (value) {
    null => const JsonNull(),
    final T present => item.write(present),
  };
}
```

Create `packages/typed_graphql_client/lib/src/operation/object_data_codec.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';
import 'data_format_exception.dart';
import 'data_object.dart';

/// Reads and writes a generated class: data, fragment or input object.
///
/// {@category operations}
final class const ObjectDataCodec<T extends DataObject>(
  /// The class's reader, a private constructor of the generated class.
  final T Function(JsonObject json, DataContext context) reader,
) extends DataCodec<T> {
  /// Creates the codec of the class [reader] reads.
  this;

  @override
  T read(JsonValue json, DataContext context) => switch (json) {
    final JsonObject object => reader(object, context),
    _ => throw DataFormatException('Expected an object, got $json.'),
  };

  @override
  JsonValue write(T value) => value.toJson();
}
```

Create `packages/typed_graphql_client/lib/src/operation/operation_document.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The document of a generated operation as it is sent (R7.9): the
/// operation and every fragment it uses, minified, with `__typename` added
/// to every selection of an object.
///
/// {@category operations}
final class const OperationDocument({
  /// The operation's name.
  required final String name,

  /// Whether it is a query, a mutation or a subscription.
  required final OperationType type,

  /// The minified document text.
  required final String text,

  /// The SHA-256 of [text] in UTF-8, in lowercase hexadecimal: the
  /// persisted query id (APQ, trusted documents).
  required final String sha256,
}) {
  /// Creates the document of the operation [name].
  this;
}
```

Create `packages/typed_graphql_client/lib/src/operation/scalar_data_codec.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'data_codec.dart';
import 'data_context.dart';
import 'data_format_exception.dart';

/// Reads and writes a scalar through its [ScalarCodec]: a built-in codec
/// or one the configuration maps a custom scalar to (R7.8).
///
/// {@category operations}
final class const ScalarDataCodec<T>(
  /// The scalar's codec.
  final ScalarCodec<T> codec,
) extends DataCodec<T> {
  /// Creates the codec of the scalar [codec] reads.
  this;

  @override
  T read(JsonValue json, DataContext context) => switch (codec.decode(json)) {
    DecodeSuccess(:final value) => value,
    DecodeFailure(:final message) => throw DataFormatException(message),
  };

  @override
  JsonValue write(T value) => codec.encode(value);
}
```

In `packages/typed_graphql_client/lib/typed_graphql_client.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,5 +2,22 @@
 /// normalized cache and MockLink, for operations generated by
 /// typed_graphql_codegen.
 ///
-/// Under construction: nothing is exported yet; see the package README.
+/// This version holds only the contract generated code compiles against:
+/// operations, data codecs and their errors. The client itself arrives in
+/// stage M11; see the package README.
 library;
+
+export 'src/operation/data_codec.dart';
+export 'src/operation/data_context.dart';
+export 'src/operation/data_enum.dart';
+export 'src/operation/data_equality.dart';
+export 'src/operation/data_format_exception.dart';
+export 'src/operation/data_object.dart';
+export 'src/operation/enum_data_codec.dart';
+export 'src/operation/graphql_operation.dart';
+export 'src/operation/json_data_codec.dart';
+export 'src/operation/list_data_codec.dart';
+export 'src/operation/nullable_data_codec.dart';
+export 'src/operation/object_data_codec.dart';
+export 'src/operation/operation_document.dart';
+export 'src/operation/scalar_data_codec.dart';
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 600 dart test test/doc/category_tags_test.dart test/doc/guide_links_test.dart test/doc/guide_snippets_test.dart test/operation/object_codecs_test.dart test/operation/support_types_test.dart test/operation/wrapper_codecs_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,7 +6,7 @@
 
 - [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, operation validation with opt-in limits and cost analysis, wire protocol and diagnostics
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
-- [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): skeleton; client runtime and normalized cache, not usable yet (M11, M12)
+- [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; reads typed_graphql.yaml and checks a project's schema and .graphql documents, does not generate code yet (M8, M10)
 - [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): skeleton; typed schema builder, executor and transport handlers, not usable yet (M5 to M7)
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
```

Append to `packages/typed_graphql_client/CHANGELOG.md`:

```markdown
- The contract generated code compiles against: `GraphQLQuery`,
  `GraphQLMutation`, `GraphQLSubscription` (sealed `GraphQLOperation`),
  `OperationDocument`, `DataCodec` with the scalar, enum, object, nullable,
  list and JSON kinds, `DataContext`, `DataEquality`, `DataEnum`,
  `DataObject` and `DataFormatException`; the Generated Operations guide.
```

In `packages/typed_graphql_client/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,11 +6,16 @@
 
 **A fully typed GraphQL client for Dart and Flutter: links, transports, a normalized cache and MockLink, for operations generated by typed_graphql_codegen.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
-> **Status: skeleton.** The package exists so the workspace, CI and the
-> code rules cover it from the start. Its code arrives in stage M11 of the
-> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.
+> **Status: under construction.** This release holds only the contract that
+> code generated by `typed_graphql_codegen` compiles against: `GraphQLQuery`,
+> `GraphQLMutation`, `GraphQLSubscription`, `OperationDocument` and the data
+> codecs (`DataCodec` and its kinds). The client itself arrives in stage M11
+> of the [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
-**Not usable yet.** This package exports nothing; the part of typed_graphql that works today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql).
+The [Generated Operations guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/doc/operations.md)
+describes the contract and shows how a decode failure reports its path. There
+is no client to send an operation yet; the part of typed_graphql that works
+today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql).
 
 Planned: `GraphQLClient`, the sealed `GraphQLResponse`, links for HTTP, WebSocket and SSE, and `MockLink` (M11); the normalized cache and `watchQuery` (M12).
 
```

Create `packages/typed_graphql_client/doc/operations.md`:

````markdown
# Generated Operations

The code that `typed_graphql_codegen` generates for an operation compiles
against the types of this package. This version holds only that contract; the
client that sends operations arrives in a later release.

## The operation

A generated operation is a `GraphQLQuery`, a `GraphQLMutation` or a
`GraphQLSubscription`, the three kinds of the sealed `GraphQLOperation`. It
holds its `OperationDocument` (name, type, minified text and the SHA-256 of
the text), its variables as JSON, and `decodeData`, which reads the `data`
member of a response. `toRequest` builds the `GraphQLRequest` to send.

## Codecs

A `DataCodec<T>` reads one kind of value of a response and writes it back.
Generated code composes them as constants:

- `ScalarDataCodec` reads a scalar through a `ScalarCodec`, such as
  `StringCodec`.
- `EnumDataCodec` reads an enum by its name; a name the schema did not have
  when the code was generated becomes an unknown value (`DataEnum`).
- `ObjectDataCodec` reads a generated class (`DataObject`).
- `NullableDataCodec` and `ListDataCodec` wrap another codec.
- `JsonDataCodec` keeps a custom scalar that is not mapped as a `JsonValue`.

`DataContext` carries the variables, which decide whether a fragment under
`@include` or `@skip` was selected. `DataEquality` compares the members of
generated classes that hold lists or optionals.

## Failures

`DataCodec.read` throws a `DataFormatException` for a value of the wrong
shape; `DataCodec.decode` never throws. It returns a `DecodeFailure` with the
message and the path of the value in the JSON it was given.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  const codec = ListDataCodec(ListDataCodec(ScalarDataCodec(StringCodec())));
  final parsed = const JsonReader().parse('[["a"], [1]]');
  if (parsed case DecodeSuccess(:final value)) {
    if (codec.decode(value) case DecodeFailure(:final message, :final path)) {
      print(message);
      print(path);
    }
  }
}
```

It prints:

```text
String cannot represent a non string value: 1
[1, 0]
```
````

- [ ] **Step 7: Run the documentation checks**

```sh
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add llms.txt packages/typed_graphql_client/CHANGELOG.md packages/typed_graphql_client/README.md packages/typed_graphql_client/dartdoc_options.yaml packages/typed_graphql_client/doc/operations.md packages/typed_graphql_client/lib/src/operation/data_codec.dart packages/typed_graphql_client/lib/src/operation/data_context.dart packages/typed_graphql_client/lib/src/operation/data_enum.dart packages/typed_graphql_client/lib/src/operation/data_equality.dart packages/typed_graphql_client/lib/src/operation/data_format_exception.dart packages/typed_graphql_client/lib/src/operation/data_object.dart packages/typed_graphql_client/lib/src/operation/enum_data_codec.dart packages/typed_graphql_client/lib/src/operation/graphql_operation.dart packages/typed_graphql_client/lib/src/operation/json_data_codec.dart packages/typed_graphql_client/lib/src/operation/list_data_codec.dart packages/typed_graphql_client/lib/src/operation/nullable_data_codec.dart packages/typed_graphql_client/lib/src/operation/object_data_codec.dart packages/typed_graphql_client/lib/src/operation/operation_document.dart packages/typed_graphql_client/lib/src/operation/scalar_data_codec.dart packages/typed_graphql_client/lib/typed_graphql_client.dart packages/typed_graphql_client/test/doc/category_tags_test.dart packages/typed_graphql_client/test/doc/guide_links_test.dart packages/typed_graphql_client/test/doc/guide_snippets_test.dart packages/typed_graphql_client/test/operation/object_codecs_test.dart packages/typed_graphql_client/test/operation/support_types_test.dart packages/typed_graphql_client/test/operation/wrapper_codecs_test.dart
git commit -q -m "feat(typed_graphql_client): add the contract generated code compiles against" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Add the Dart writer, names and imports

The internal emitter base in `lib/src/emit/`: `DartWriter` (two-space blocks, fenced doc comments, argument lists that wrap at 80 columns as the formatter does), `DartStringLiteral` (any text as a valid Dart literal), `DartNames` (type and member names from GraphQL names, `$` for reserved words and members), `Imports` (sorted, prefixed) and `GeneratedHeader` (`// dart format off`).

Commit on the branch: `8c5832f`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`, `packages/typed_graphql_codegen/lib/src/emit/dart_string_literal.dart`, `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart`, `packages/typed_graphql_codegen/lib/src/emit/generated_header.dart`, `packages/typed_graphql_codegen/lib/src/emit/imports.dart`
- Test: `packages/typed_graphql_codegen/test/emit/dart_names_test.dart`, `packages/typed_graphql_codegen/test/emit/dart_string_literal_test.dart`, `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart`, `packages/typed_graphql_codegen/test/emit/generated_header_test.dart`, `packages/typed_graphql_codegen/test/emit/imports_test.dart`

**Interfaces:**
- Consumes: Nothing from earlier tasks.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// emit/dart_names.dart
final class DartNames
  const DartNames()
  String typeName(String name)
  String memberName(String name,
  String capitalized(String memberName)

// emit/dart_string_literal.dart
final class DartStringLiteral
  const DartStringLiteral()
  String of(String value)

// emit/dart_writer.dart
final class DartWriter
  DartWriter()
  void line([String text = ''])
  void indented(void Function() body)
  void block(String header, void Function() body)
  void doc(String text)
  void items(String open, List<String> items, String close)
  String get text

// emit/generated_header.dart
final class GeneratedHeader
  const GeneratedHeader()
  void write(DartWriter writer,

// emit/imports.dart
final class Imports
  Imports()
  void package(String uri,
  void relative(String path,
  String prefixFor(String uri)
  void write(DartWriter writer)
final class _Import
  final String uri
  final String? prefix
  String get text
  static int compare(_Import a, _Import b)
  int get hashCode
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/emit/dart_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/dart_names.dart';

void main() {
  const DartNames names = DartNames();

  final Map<String, String> types = <String, String>{
    'user': 'User',
    'User': 'User',
    'UUID': 'UUID',
    'USER_ROLE': 'UserRole',
    'user_role': 'UserRole',
    '__Schema': r'$$Schema',
    '_foo_bar': r'$FooBar',
    'A_B': 'AB',
    'Get_user': 'GetUser',
  };
  types.forEach((name, dart) {
    test('typeName of $name', () => expect(names.typeName(name), dart));
  });

  final Map<String, String> members = <String, String>{
    '__typename': 'typename',
    'ID': 'id',
    'ADMIN': 'admin',
    'UserName': 'userName',
    'createdAt': 'createdAt',
    'NOT_FOUND': 'notFound',
    'user_name': 'userName',
    'user_ID': 'userId',
    '_id': r'$id',
    '__x': r'$$x',
    'default': r'default$',
    'class': r'class$',
    'in': r'in$',
  };
  members.forEach((name, dart) {
    test('memberName of $name', () => expect(names.memberName(name), dart));
  });

  test('memberName escapes a reserved member', () {
    expect(
      names.memberName('toJson', reservedMembers: DartNames.objectMembers),
      r'toJson$',
    );
  });

  test('memberName leaves a member the caller did not reserve', () {
    expect(names.memberName('toJson'), 'toJson');
  });

  test('enum members include the members of Enum', () {
    expect(
      <bool>[
        for (final String name in <String>['values', 'index', 'name'])
          DartNames.enumMembers.contains(name),
      ],
      <bool>[true, true, true],
    );
  });

  test('capitalized upper-cases the first character', () {
    expect(
      <String>[
        names.capitalized('userName'),
        names.capitalized(r'$id'),
        names.capitalized(r'default$'),
      ],
      <String>['UserName', r'$id', r'Default$'],
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/emit/dart_string_literal_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/dart_string_literal.dart';

void main() {
  const DartStringLiteral literal = DartStringLiteral();

  final Map<String, String> expected = <String, String>{
    'plain': "'plain'",
    '': "''",
    r'a\b': r"r'a\b'",
    r'$x': r"r'$x'",
    "it's": '"it\'s"',
    r"it's $x": 'r"it\'s \$x"',
    'say "hi" it\'s': '\'say "hi" it\\\'s\'',
    'a\nb': r"'a\nb'",
    'a\tb\rc': r"'a\tb\rc'",
    '\u0001': r"'\u{1}'",
    '\u007f': r"'\u{7F}'",
    r"\'": r'''r"\'"''',
    r'''\'"''': r"""'\\\'"'""",
    'x\n\$y': r"'x\n\$y'",
    '\u{D800}': r"'\u{D800}'",
    'a\u{DC00}': r"'a\u{DC00}'",
    '\u{1F600}': "'\u{1F600}'",
  };

  expected.forEach((value, text) {
    test('literal of ${value.codeUnits}', () {
      expect(literal.of(value), text);
    });
  });
}
```

Create `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart`:

````dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';

void main() {
  test('line indents and leaves empty lines bare', () {
    final DartWriter writer = DartWriter();
    writer.indented(() {
      writer.line('a');
      writer.line();
    });
    writer.line('b');
    expect(writer.text, '  a\n\nb\n');
  });

  test('block nests its body', () {
    final DartWriter writer = DartWriter();
    writer.block('class A', () {
      writer.block('void f()', () => writer.line('x();'));
    });
    expect(writer.text, 'class A {\n  void f() {\n    x();\n  }\n}\n');
  });

  test('doc writes one comment line per line', () {
    final DartWriter writer = DartWriter();
    writer.doc('First.\n\nSecond.');
    expect(writer.text, '/// First.\n///\n/// Second.\n');
  });

  test('doc gives an opening bare fence the text language', () {
    final DartWriter writer = DartWriter();
    writer.doc('A.\n```\ncode\n```\nB.\n```\nmore\n```');
    expect(
      writer.text,
      '/// A.\n/// ```text\n/// code\n/// ```\n/// B.\n'
      '/// ```text\n/// more\n/// ```\n',
    );
  });

  test('doc keeps a fence that already has a language', () {
    final DartWriter writer = DartWriter();
    writer.doc('```dart\nx\n```');
    expect(writer.text, '/// ```dart\n/// x\n/// ```\n');
  });

  test('items stays on one line at exactly 80 columns', () {
    final DartWriter writer = DartWriter();
    final String filler = 'a' * (80 - 'const X({'.length - '});'.length);
    writer.items('const X({', <String>[filler], '});');
    expect(writer.text, 'const X({$filler});\n');
    expect(writer.text.trimRight().length, 80);
  });

  test('items splits at 81 columns', () {
    final DartWriter writer = DartWriter();
    final String filler = 'a' * (81 - 'const X({'.length - '});'.length);
    writer.items('const X({', <String>[filler], '});');
    expect(writer.text, 'const X({\n  $filler,\n});\n');
  });

  test('items counts the indentation', () {
    final DartWriter writer = DartWriter();
    final String filler = 'a' * (79 - 'f('.length - ')'.length);
    writer.indented(() => writer.items('f(', <String>[filler], ')'));
    expect(writer.text, '  f(\n    $filler,\n  )\n');
  });

  test('items joins several items with a comma', () {
    final DartWriter writer = DartWriter();
    writer.items('f(', <String>['a', 'b'], ');');
    expect(writer.text, 'f(a, b);\n');
  });

  test('text of an empty writer is empty', () {
    expect(DartWriter().text, '');
  });
}
````

Create `packages/typed_graphql_codegen/test/emit/generated_header_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/generated_header.dart';

void main() {
  test('write names the source and turns the formatter off', () {
    final DartWriter writer = DartWriter();
    const GeneratedHeader().write(writer, source: 'lib/user.graphql');
    writer.line('x');
    expect(
      writer.text,
      '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
      '// Generated by typed_graphql_codegen from lib/user.graphql.\n'
      '// dart format off\n'
      '\n'
      'x\n',
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/emit/imports_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';

void main() {
  test('write orders the groups and sorts each', () {
    final Imports imports = Imports()
      ..relative('schema.graphql.dart')
      ..package(
        'package:typed_graphql_client/typed_graphql_client.dart',
        prefix: 'client',
      )
      ..package('package:typed_graphql/typed_graphql.dart', prefix: 'graphql')
      ..package('dart:convert')
      ..relative('codecs.dart', prefix: 'scalar_0')
      ..package('dart:async');
    final DartWriter writer = DartWriter();
    imports.write(writer);
    expect(
      writer.text,
      "import 'dart:async';\n"
      "import 'dart:convert';\n"
      '\n'
      "import 'package:typed_graphql/typed_graphql.dart' as graphql;\n"
      "import 'package:typed_graphql_client/typed_graphql_client.dart' "
      'as client;\n'
      '\n'
      "import 'codecs.dart' as scalar_0;\n"
      "import 'schema.graphql.dart';\n",
    );
  });

  test('write omits empty groups and their blank lines', () {
    final Imports imports = Imports()..relative('a.dart');
    final DartWriter writer = DartWriter();
    imports.write(writer);
    expect(writer.text, "import 'a.dart';\n");
  });

  test('prefixFor counts from zero and repeats a known uri', () {
    final Imports imports = Imports();
    expect(
      <String>[
        imports.prefixFor('package:money/money.dart'),
        imports.prefixFor('dart:typed_data'),
        imports.prefixFor('package:money/money.dart'),
      ],
      <String>['scalar_0', 'scalar_1', 'scalar_0'],
    );
  });

  test('prefixFor records the import once', () {
    final Imports imports = Imports();
    imports.prefixFor('package:money/money.dart');
    imports.prefixFor('package:money/money.dart');
    final DartWriter writer = DartWriter();
    imports.write(writer);
    expect(writer.text, "import 'package:money/money.dart' as scalar_0;\n");
  });

  test('one uri with two prefixes is written twice', () {
    final Imports imports = Imports()
      ..package('package:a/a.dart', prefix: 'x')
      ..package('package:a/a.dart', prefix: 'y');
    final DartWriter writer = DartWriter();
    imports.write(writer);
    expect(
      writer.text,
      "import 'package:a/a.dart' as x;\nimport 'package:a/a.dart' as y;\n",
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/dart_names_test.dart test/emit/dart_string_literal_test.dart test/emit/dart_writer_test.dart test/emit/generated_header_test.dart test/emit/imports_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`:

```dart
/// Turns GraphQL names into Dart identifiers.
///
/// GraphQL names cannot contain `$`, so a `$` added here never collides with
/// another GraphQL name.
///
/// {@category codegen}
final class DartNames {
  /// Creates the name converter.
  const DartNames();

  /// Members every generated data or input class has.
  static const Set<String> objectMembers = <String>{
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
    'toJson',
    'codec',
    'decode',
    'fragments',
  };

  /// Members every generated enum has, including those of `Enum`.
  static const Set<String> enumMembers = <String>{
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
    'values',
    'index',
    'name',
    'raw',
    'codec',
    'parse',
  };

  static const Set<String> _reservedWords = <String>{
    'assert',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'in',
    'is',
    'new',
    'null',
    'rethrow',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',
  };

  /// A class name from a GraphQL type, operation or fragment name.
  String typeName(String name) {
    final (String prefix, String rest) = _splitUnderscores(name);
    if (!rest.contains('_')) {
      return '$prefix${_upperFirst(rest)}';
    }
    final StringBuffer out = StringBuffer(prefix);
    for (final String part in _parts(rest)) {
      out.write(
        _isUpperCase(part) && part.length > 1
            ? _titleCase(part)
            : _upperFirst(part),
      );
    }
    return out.toString();
  }

  /// A field, variable, argument or enum value name.
  ///
  /// A reserved word or a member in [reservedMembers] gets a `$` suffix.
  String memberName(String name, {Set<String> reservedMembers = const {}}) {
    if (name == '__typename') {
      return 'typename';
    }
    final (String prefix, String rest) = _splitUnderscores(name);
    final List<String> parts = _parts(rest);
    final StringBuffer out = StringBuffer(prefix);
    if (parts.isNotEmpty) {
      out.write(_firstPart(parts.first));
      for (final String part in parts.skip(1)) {
        out.write(_isUpperCase(part) ? _titleCase(part) : _upperFirst(part));
      }
    }
    final String result = out.toString();
    if (_reservedWords.contains(result) || reservedMembers.contains(result)) {
      return '$result\$';
    }
    return result;
  }

  /// [memberName] with its first character upper-cased, `$` kept.
  String capitalized(String memberName) => _upperFirst(memberName);

  String _firstPart(String part) {
    if (_isUpperCase(part)) {
      return part.toLowerCase();
    }
    return '${part[0].toLowerCase()}${part.substring(1)}';
  }

  (String, String) _splitUnderscores(String name) {
    int count = 0;
    while (count < name.length && name[count] == '_') {
      count++;
    }
    return (r'$' * count, name.substring(count));
  }

  List<String> _parts(String rest) =>
      rest.split('_').where((part) => part.isNotEmpty).toList();

  bool _isUpperCase(String part) {
    for (final int unit in part.codeUnits) {
      final bool isUpper = unit >= 0x41 && unit <= 0x5a;
      final bool isDigit = unit >= 0x30 && unit <= 0x39;
      if (!isUpper && !isDigit) {
        return false;
      }
    }
    return part.isNotEmpty;
  }

  String _titleCase(String part) =>
      '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';

  String _upperFirst(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/dart_string_literal.dart`:

```dart
/// Writes a Dart string literal that satisfies `prefer_single_quotes` and
/// `use_raw_strings`.
///
/// {@category codegen}
final class DartStringLiteral {
  /// Creates the writer.
  const DartStringLiteral();

  /// The Dart literal for [value].
  String of(String value) {
    final bool isPlain = !_hasControlOrSurrogate(value);
    final bool needsRaw = value.contains(r'\') || value.contains(r'$');
    if (isPlain && !value.contains("'")) {
      return needsRaw ? "r'$value'" : "'$value'";
    }
    if (isPlain && !value.contains('"')) {
      return needsRaw ? 'r"$value"' : '"$value"';
    }
    return _escaped(value);
  }

  bool _hasControlOrSurrogate(String value) {
    final List<int> units = value.codeUnits;
    for (int index = 0; index < units.length; index++) {
      final int unit = units[index];
      if (unit < 0x20 || unit == 0x7f) {
        return true;
      }
      if (_isHighSurrogate(unit) &&
          index + 1 < units.length &&
          _isLowSurrogate(units[index + 1])) {
        index++;
      } else if (_isHighSurrogate(unit) || _isLowSurrogate(unit)) {
        return true;
      }
    }
    return false;
  }

  bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  String _escaped(String value) {
    final StringBuffer out = StringBuffer("'");
    final List<int> units = value.codeUnits;
    for (int index = 0; index < units.length; index++) {
      final int unit = units[index];
      if (_isHighSurrogate(unit) &&
          index + 1 < units.length &&
          _isLowSurrogate(units[index + 1])) {
        out.write(String.fromCharCodes(<int>[unit, units[index + 1]]));
        index++;
      } else {
        out.write(_escapedUnit(unit));
      }
    }
    out.write("'");
    return out.toString();
  }

  String _escapedUnit(int unit) {
    return switch (unit) {
      0x5c => r'\\',
      0x27 => r"\'",
      0x24 => r'\$',
      0x0a => r'\n',
      0x0d => r'\r',
      0x09 => r'\t',
      _ when unit < 0x20 || unit == 0x7f || _isSurrogate(unit) =>
        '\\u{${unit.toRadixString(16).toUpperCase()}}',
      _ => String.fromCharCode(unit),
    };
  }

  bool _isSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDFFF;
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart`:

````dart
/// A text builder for generated Dart code.
///
/// {@category codegen}
final class DartWriter {
  /// Creates an empty writer at indentation level zero.
  DartWriter();

  static const int _maxColumns = 80;

  final StringBuffer _buffer = StringBuffer();
  int _level = 0;
  bool _isInFence = false;

  String get _indentation => '  ' * _level;

  /// Writes [text] as one line at the current indentation.
  ///
  /// An empty line has no trailing spaces.
  void line([String text = '']) {
    if (text.isEmpty) {
      _buffer.writeln();
    } else {
      _buffer.writeln('$_indentation$text');
    }
  }

  /// Runs [body] one indentation level deeper.
  void indented(void Function() body) {
    _level++;
    try {
      body();
    } finally {
      _level--;
    }
  }

  /// Writes `header {`, the [body] one level deeper, and `}`.
  void block(String header, void Function() body) {
    line('$header {');
    indented(body);
    line('}');
  }

  /// Writes [text] as a `///` comment, one comment line per line of [text].
  ///
  /// A bare Markdown fence that opens a block gets the language `text`.
  void doc(String text) {
    for (final String content in text.split('\n')) {
      line(_docLine(content));
    }
  }

  String _docLine(String content) {
    final String trimmed = content.trim();
    if (trimmed.startsWith('```')) {
      if (_isInFence) {
        _isInFence = false;
      } else {
        _isInFence = true;
        if (trimmed == '```') {
          return '/// ```text';
        }
      }
    }
    return content.isEmpty ? '///' : '/// $content';
  }

  /// Writes `open + items.join(', ') + close` on one line when it fits in 80
  /// columns, otherwise one item per line, each ending with `,`.
  void items(String open, List<String> items, String close) {
    final String single = '$open${items.join(', ')}$close';
    if (_indentation.length + single.length <= _maxColumns) {
      line(single);
      return;
    }
    line(open);
    indented(() {
      for (final String item in items) {
        line('$item,');
      }
    });
    line(close);
  }

  /// Everything written; ends with exactly one line break.
  String get text {
    final String written = _buffer.toString().trimRight();
    return written.isEmpty ? '' : '$written\n';
  }
}
````

Create `packages/typed_graphql_codegen/lib/src/emit/generated_header.dart`:

```dart
import 'dart_writer.dart';

/// Writes the header every generated file starts with.
///
/// {@category codegen}
final class GeneratedHeader {
  /// Creates the header writer.
  const GeneratedHeader();

  /// Writes the header for a file generated from [source].
  void write(DartWriter writer, {required String source}) {
    writer
      ..line('// GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..line('// Generated by typed_graphql_codegen from $source.')
      ..line('// dart format off')
      ..line();
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/imports.dart`:

```dart
import 'dart_writer.dart';

/// Collects the imports of one generated library and writes them in
/// `directives_ordering` order.
///
/// {@category codegen}
final class Imports {
  /// Creates an empty collection.
  Imports();

  final List<_Import> _dart = <_Import>[];
  final List<_Import> _package = <_Import>[];
  final List<_Import> _relative = <_Import>[];
  final Map<String, String> _scalarPrefixes = <String, String>{};

  /// Records `import '[uri]'` of a `dart:` or `package:` library.
  void package(String uri, {String? prefix}) {
    _add(uri.startsWith('dart:') ? _dart : _package, _Import(uri, prefix));
  }

  /// Records `import '[path]'` of a library of the same package.
  void relative(String path, {String? prefix}) {
    _add(_relative, _Import(path, prefix));
  }

  /// The prefix of the custom scalar library [uri], recorded as an import.
  ///
  /// Prefixes are `scalar_0`, `scalar_1`, ... in order of first request.
  String prefixFor(String uri) {
    final String? known = _scalarPrefixes[uri];
    if (known != null) {
      return known;
    }
    final String prefix = 'scalar_${_scalarPrefixes.length}';
    _scalarPrefixes[uri] = prefix;
    package(uri, prefix: prefix);
    return prefix;
  }

  /// Writes the imports, `dart:` first, then `package:`, then relative.
  void write(DartWriter writer) {
    bool isFirst = true;
    for (final List<_Import> group in <List<_Import>>[
      _dart,
      _package,
      _relative,
    ]) {
      if (group.isEmpty) {
        continue;
      }
      if (!isFirst) {
        writer.line();
      }
      isFirst = false;
      final List<_Import> sorted = <_Import>[...group]..sort(_Import.compare);
      for (final _Import import in sorted) {
        writer.line(import.text);
      }
    }
  }

  void _add(List<_Import> group, _Import import) {
    if (!group.contains(import)) {
      group.add(import);
    }
  }
}

final class _Import {
  const _Import(this.uri, this.prefix);

  final String uri;
  final String? prefix;

  String get text =>
      prefix == null ? "import '$uri';" : "import '$uri' as $prefix;";

  static int compare(_Import a, _Import b) {
    final int byUri = a.uri.compareTo(b.uri);
    return byUri != 0 ? byUri : (a.prefix ?? '').compareTo(b.prefix ?? '');
  }

  @override
  bool operator ==(Object other) =>
      other is _Import && other.uri == uri && other.prefix == prefix;

  @override
  int get hashCode => Object.hash(uri, prefix);
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/dart_names_test.dart test/emit/dart_string_literal_test.dart test/emit/dart_writer_test.dart test/emit/generated_header_test.dart test/emit/imports_test.dart)
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
git add packages/typed_graphql_codegen/lib/src/emit/dart_names.dart packages/typed_graphql_codegen/lib/src/emit/dart_string_literal.dart packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart packages/typed_graphql_codegen/lib/src/emit/generated_header.dart packages/typed_graphql_codegen/lib/src/emit/imports.dart packages/typed_graphql_codegen/test/emit/dart_names_test.dart packages/typed_graphql_codegen/test/emit/dart_string_literal_test.dart packages/typed_graphql_codegen/test/emit/dart_writer_test.dart packages/typed_graphql_codegen/test/emit/generated_header_test.dart packages/typed_graphql_codegen/test/emit/imports_test.dart
git commit -q -m "feat(typed_graphql_codegen): add the Dart writer, names and imports" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Map GraphQL types to Dart and emit enums

`DartType` and `TypeMapper` map a named or wrapped GraphQL type to a Dart type and a codec expression with a loop, not recursion (R7.8). `EnumEmitter` writes an enum as a sealed class implementing `client.DataEnum`, a `…Known` enum with one value per GraphQL value (`@Deprecated` from `@deprecated`) and a `…Unknown` class, so a `switch` is exhaustive and still compiles when the server adds a value (R7.6; spec deviation 1). `parse` loops over the known values.

Commit on the branch: `5eb47bb`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/emit/dart_type.dart`, `packages/typed_graphql_codegen/lib/src/emit/enum_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/type_mapper.dart`
- Test: `packages/typed_graphql_codegen/test/emit/enum_emitter_test.dart`, `packages/typed_graphql_codegen/test/emit/type_mapper_test.dart`

**Interfaces:**
- Consumes: Task 3 (`DartWriter`, `DartNames`, `DartStringLiteral`); Task 2 (the codec kinds the expressions name).
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// emit/dart_type.dart
final class const DartType(…)
  int get hashCode
  String toString()

// emit/enum_emitter.dart
final class EnumEmitter
  const EnumEmitter()
  void emit(EnumType type, DartWriter writer)

// emit/type_mapper.dart
final class TypeMapper
  const TypeMapper(this.schema, this.scalars)
  final Schema schema
  final Map<String, ScalarMapping> scalars
  DartType named(String typeName, Imports imports,
  DartType of(TypeRef type, Imports imports,
  DartType ofNonNull(TypeRef type, Imports imports,
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/emit/enum_emitter_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/enum_emitter.dart';

void main() {
  String emit(String sdl, String name) {
    final document = const Parser().parse(Source(sdl)).requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    final DartWriter writer = DartWriter();
    const EnumEmitter().emit(schema.typeNamed(name)! as EnumType, writer);
    return writer.text;
  }

  test('an enum with descriptions and deprecations', () {
    expect(
      emit('''
"A user role."
enum Role {
  ADMIN
  EDITOR
  "Old."
  VIEWER @deprecated(reason: "Use EDITOR.")
  GUEST @deprecated
}
''', 'Role'),
      r'''
/// A user role.
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

  /// `EDITOR`.
  editor('EDITOR'),

  /// Old.
  @Deprecated('Use EDITOR.')
  viewer('VIEWER'),

  /// `GUEST`.
  @Deprecated('No longer supported')
  guest('GUEST');

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
''',
    );
  });

  test('values that clash with Dart get a suffix or are camel-cased', () {
    final String text = emit(
      'enum Odd { values NOT_FOUND default }',
      'Odd',
    );
    expect(
      text.split('\n').where(RegExp(r"^  \S+\('").hasMatch),
      [
        r"  values$('values'),",
        "  notFound('NOT_FOUND'),",
        r"  default$('default');",
      ],
    );
  });

  test('the type without a description is documented by its name', () {
    expect(
      emit('enum Odd { A }', 'Odd').startsWith('/// The enum `Odd`.\n'),
      isTrue,
    );
  });

  test('the unknown class escapes a dollar in its name', () {
    expect(
      emit('enum _Odd { A }', '_Odd'),
      contains(r"String toString() => '\$OddUnknown($raw)';"),
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/emit/type_mapper_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/config/dart_reference.dart';
import 'package:typed_graphql_codegen/src/config/scalar_mapping.dart';
import 'package:typed_graphql_codegen/src/emit/dart_type.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';

const _sdl = '''
type Query { a: Int }
type User { name: String }
interface Node { id: ID }
union Result = User
enum Role { ADMIN }
input Filter { name: String }
scalar Date
scalar Money
scalar Blob
''';

void main() {
  Schema schema() {
    final document = const Parser().parse(Source(_sdl)).requireDocument();
    return (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
  }

  TypeRef type(String text) {
    final document = const Parser()
        .parse(Source('type Probe { f: $text }'))
        .requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    return (schema.typeNamed('Probe')! as ObjectType).fields.first.type;
  }

  final TypeMapper mapper = TypeMapper(schema(), const {
    'Date': ScalarMapping(
      DartReference(null, 'DateTime'),
      DartReference('package:a/codecs.dart', 'DateTimeCodec'),
    ),
    'Money': ScalarMapping(
      DartReference('package:a/money.dart', 'Money'),
      DartReference('package:a/money.dart', 'MoneyCodec'),
    ),
  });

  final builtIns = <String, DartType>{
    'String': const DartType(
      'String',
      'client.ScalarDataCodec(graphql.StringCodec())',
    ),
    'ID': const DartType('String', 'client.ScalarDataCodec(graphql.IdCodec())'),
    'Int': const DartType('int', 'client.ScalarDataCodec(graphql.IntCodec())'),
    'Float': const DartType(
      'double',
      'client.ScalarDataCodec(graphql.FloatCodec())',
    ),
    'Boolean': const DartType(
      'bool',
      'client.ScalarDataCodec(graphql.BooleanCodec())',
    ),
  };
  builtIns.forEach((name, expected) {
    test('$name maps to its built-in codec', () {
      expect(mapper.named(name, Imports()), expected);
    });
  });

  test('a mapped scalar of dart:core needs no prefix for its type', () {
    final Imports imports = Imports();
    expect(
      mapper.named('Date', imports),
      const DartType(
        'DateTime',
        'client.ScalarDataCodec(scalar_0.DateTimeCodec())',
      ),
    );
  });

  test('a mapped scalar of a package is prefixed and imported', () {
    final Imports imports = Imports();
    expect(
      mapper.named('Money', imports),
      const DartType(
        'scalar_0.Money',
        'client.ScalarDataCodec(scalar_0.MoneyCodec())',
      ),
    );
    expect(imports.prefixFor('package:a/money.dart'), 'scalar_0');
  });

  test('an unmapped custom scalar is a JsonValue', () {
    expect(
      mapper.named('Blob', Imports()),
      const DartType('graphql.JsonValue', 'client.JsonDataCodec()'),
    );
  });

  test('an enum maps to its class and codec', () {
    expect(
      mapper.named('Role', Imports()),
      const DartType('Role', 'Role.codec'),
    );
  });

  test('an input object maps to its class and codec', () {
    expect(
      mapper.named('Filter', Imports()),
      const DartType('Filter', 'Filter.codec'),
    );
  });

  test('an object maps to the class the caller chose', () {
    expect(
      mapper.named('User', Imports(), objectClass: 'GetUserUser'),
      const DartType('GetUserUser', 'GetUserUser.codec'),
    );
  });

  test('an object without objectClass is an ArgumentError', () {
    expect(
      () => mapper.named('User', Imports()),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('an unknown type is an ArgumentError', () {
    expect(
      () => mapper.named('Nope', Imports()),
      throwsA(isA<ArgumentError>()),
    );
  });

  const string = 'client.ScalarDataCodec(graphql.StringCodec())';

  test('[String!]! has no nullable level', () {
    expect(
      mapper.of(type('[String!]!'), Imports()),
      const DartType('List<String>', 'client.ListDataCodec($string)'),
    );
  });

  test('[String] is nullable in its items and as a whole', () {
    expect(
      mapper.of(type('[String]'), Imports()),
      const DartType(
        'List<String?>?',
        'client.NullableDataCodec(client.ListDataCodec('
            'client.NullableDataCodec($string)))',
      ),
    );
  });

  test('[[Int!]]! nests lists', () {
    const int_ = 'client.ScalarDataCodec(graphql.IntCodec())';
    expect(
      mapper.of(type('[[Int!]]!'), Imports()),
      const DartType(
        'List<List<int>?>',
        'client.ListDataCodec(client.NullableDataCodec('
            'client.ListDataCodec($int_)))',
      ),
    );
  });

  test('ofNonNull removes the outermost nullability only', () {
    expect(
      mapper.ofNonNull(type('[String]'), Imports()),
      const DartType(
        'List<String?>',
        'client.ListDataCodec(client.NullableDataCodec($string))',
      ),
    );
  });

  test('ofNonNull keeps a non-null type non-null', () {
    expect(
      mapper.ofNonNull(type('String!'), Imports()),
      const DartType('String', string),
    );
  });

  test('a list nested 200 levels deep maps', () {
    TypeRef nested = const NamedType(Name('String'));
    for (int depth = 0; depth < 200; depth++) {
      nested = ListType(nested);
    }
    final DartType type = mapper.of(nested, Imports());
    expect(type.type, '${'List<' * 200}String?${'>?' * 200}');
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/enum_emitter_test.dart test/emit/type_mapper_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_codegen/lib/src/emit/dart_type.dart`:

```dart
/// A Dart type as written in generated code, with the codec that reads and
/// writes its values.
///
/// {@category codegen}
final class const DartType(
  /// The type as written, such as `List<String>?`.
  final String type,

  /// The constant expression of the codec, without `const` (it always stands
  /// in a constant context).
  final String codec,
) {
  /// Creates a type and its codec.
  this;

  @override
  bool operator ==(Object other) =>
      other is DartType && other.type == type && other.codec == codec;

  @override
  int get hashCode => Object.hash(type, codec);

  @override
  String toString() => 'DartType($type, $codec)';
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/enum_emitter.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';

/// Writes the Dart declarations of a GraphQL enum (spec §7 "Enums"): a sealed
/// class, the enum of the known values and the class of an unknown one.
///
/// {@category codegen}
final class EnumEmitter {
  /// Creates the emitter.
  const EnumEmitter();

  static const DartNames _names = DartNames();
  static const DartStringLiteral _literal = DartStringLiteral();

  /// Writes the three declarations of [type] to [writer].
  void emit(EnumType type, DartWriter writer) {
    final String name = _names.typeName(type.name);
    _writeSealed(type, name, writer);
    writer.line();
    _writeKnown(type, name, writer);
    writer.line();
    _writeUnknown(name, writer);
  }

  void _writeSealed(EnumType type, String name, DartWriter writer) {
    writer
      ..doc(type.description ?? 'The enum `${type.name}`.')
      ..block('sealed class $name implements client.DataEnum', () {
        writer
          ..doc(
            'The value named [raw]: a [${name}Known], or a [${name}Unknown] '
            'for a name\nthis code does not know.',
          )
          ..block('factory $name.parse(String raw)', () {
            writer
              ..block('for (final value in ${name}Known.values)', () {
                writer.line('if (value.raw == raw) return value;');
              })
              ..line('return ${name}Unknown(raw);');
          })
          ..line()
          ..doc('Reads and writes the values of `${type.name}`.')
          ..line(
            'static const client.DataCodec<$name> codec = '
            'client.EnumDataCodec($name.parse);',
          );
      });
  }

  void _writeKnown(EnumType type, String name, DartWriter writer) {
    writer
      ..doc('The values of [$name] this code knows.')
      ..block('enum ${name}Known implements $name', () {
        for (final (int index, SchemaEnumValue value) in type.values.indexed) {
          _writeValue(value, index == type.values.length - 1, writer);
          writer.line();
        }
        writer
          ..line('const ${name}Known(this.raw);')
          ..line()
          ..line('@override')
          ..line('final String raw;');
      });
  }

  void _writeValue(SchemaEnumValue value, bool isLast, DartWriter writer) {
    writer.doc(value.description ?? '`${value.name}`.');
    final String? reason = value.deprecationReason;
    if (reason != null) {
      writer.line('@Deprecated(${_literal.of(reason)})');
    }
    final String member = _names.memberName(
      value.name,
      reservedMembers: DartNames.enumMembers,
    );
    writer.line("$member(${_literal.of(value.name)})${isLast ? ';' : ','}");
  }

  void _writeUnknown(String name, DartWriter writer) {
    final String interpolated = '${name}Unknown'.replaceAll(r'$', r'\$');
    writer
      ..doc(
        'A value of [$name] this code does not know, such as one added to '
        'the\nschema after the code was generated.',
      )
      ..block('final class ${name}Unknown implements $name', () {
        writer
          ..doc('Creates the value named [raw].')
          ..line('const ${name}Unknown(this.raw);')
          ..line()
          ..line('@override')
          ..line('final String raw;')
          ..line()
          ..line('@override')
          ..line(
            'bool operator ==(Object other) => '
            'other is ${name}Unknown && other.raw == raw;',
          )
          ..line()
          ..line('@override')
          ..line('int get hashCode => raw.hashCode;')
          ..line()
          ..line('@override')
          ..line("String toString() => '$interpolated(\$raw)';");
      });
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/type_mapper.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../config/dart_reference.dart';
import '../config/scalar_mapping.dart';
import 'dart_names.dart';
import 'dart_type.dart';
import 'imports.dart';

/// Maps GraphQL types to the Dart types of generated code and their codecs
/// (spec §7 "Scalars", R7.6, R7.8).
///
/// {@category codegen}
final class TypeMapper {
  /// Creates a mapper over [schema] with the configured custom [scalars].
  const TypeMapper(this.schema, this.scalars);

  /// The schema the type names belong to.
  final Schema schema;

  /// The custom scalar mappings, by scalar name.
  final Map<String, ScalarMapping> scalars;

  static const Map<String, (String, String)> _builtIns =
      <String, (String, String)>{
        'String': ('String', 'StringCodec'),
        'ID': ('String', 'IdCodec'),
        'Int': ('int', 'IntCodec'),
        'Float': ('double', 'FloatCodec'),
        'Boolean': ('bool', 'BooleanCodec'),
      };

  /// The non-null Dart type of the named type [typeName].
  ///
  /// [objectClass] is the generated class an object, interface or union type
  /// maps to; omitting it for one of those is an [ArgumentError].
  DartType named(String typeName, Imports imports, {String? objectClass}) {
    final (String, String)? builtIn = _builtIns[typeName];
    if (builtIn != null) {
      return DartType(
        builtIn.$1,
        'client.ScalarDataCodec(graphql.${builtIn.$2}())',
      );
    }
    return switch (schema.typeNamed(typeName)) {
      ScalarType() => _customScalar(typeName, imports),
      EnumType() || InputObjectType() => _generated(
        const DartNames().typeName(typeName),
      ),
      ObjectType() || InterfaceType() || UnionType() => _generated(
        objectClass ??
            (throw ArgumentError.value(
              objectClass,
              'objectClass',
              'is required for the composite type $typeName',
            )),
      ),
      null => throw ArgumentError.value(
        typeName,
        'typeName',
        'is not a type of the schema',
      ),
    };
  }

  /// The full Dart type of [type], nullable unless wrapped in a non-null.
  DartType of(TypeRef type, Imports imports, {String? objectClass}) =>
      _build(type, imports, objectClass, isOuterNullable: null);

  /// [of] with the outermost nullability removed.
  DartType ofNonNull(TypeRef type, Imports imports, {String? objectClass}) =>
      _build(type, imports, objectClass, isOuterNullable: false);

  DartType _build(
    TypeRef type,
    Imports imports,
    String? objectClass, {
    required bool? isOuterNullable,
  }) {
    // Nullability of each level, outside in: every list, then the named type.
    final List<bool> levels = <bool>[];
    bool isNullable = true;
    TypeRef current = type;
    while (true) {
      switch (current) {
        case NonNullType(type: final inner):
          isNullable = false;
          current = inner;
        case ListType(type: final inner):
          levels.add(isNullable);
          isNullable = true;
          current = inner;
        case NamedType(:final name):
          levels.add(isNullable);
          if (isOuterNullable != null) {
            levels[0] = isOuterNullable;
          }
          return _wrap(
            named(name.value, imports, objectClass: objectClass),
            levels,
          );
      }
    }
  }

  DartType _wrap(DartType base, List<bool> levels) {
    String type = base.type;
    String codec = base.codec;
    for (int index = levels.length - 1; index >= 0; index--) {
      if (levels[index]) {
        type = '$type?';
        codec = 'client.NullableDataCodec($codec)';
      }
      if (index > 0) {
        type = 'List<$type>';
        codec = 'client.ListDataCodec($codec)';
      }
    }
    return DartType(type, codec);
  }

  DartType _generated(String className) =>
      DartType(className, '$className.codec');

  DartType _customScalar(String name, Imports imports) {
    final ScalarMapping? mapping = scalars[name];
    if (mapping == null) {
      return const DartType('graphql.JsonValue', 'client.JsonDataCodec()');
    }
    return DartType(
      _reference(mapping.type, imports),
      'client.ScalarDataCodec(${_reference(mapping.codec, imports)}())',
    );
  }

  String _reference(DartReference reference, Imports imports) =>
      switch (reference.library) {
        final String library =>
          '${imports.prefixFor(library)}.${reference.name}',
        null => reference.name,
      };
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/enum_emitter_test.dart test/emit/type_mapper_test.dart)
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
git add packages/typed_graphql_codegen/lib/src/emit/dart_type.dart packages/typed_graphql_codegen/lib/src/emit/enum_emitter.dart packages/typed_graphql_codegen/lib/src/emit/type_mapper.dart packages/typed_graphql_codegen/test/emit/enum_emitter_test.dart packages/typed_graphql_codegen/test/emit/type_mapper_test.dart
git commit -q -m "feat(typed_graphql_codegen): map GraphQL types to Dart and emit enums" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Emit input objects

`InputField` holds the per-field rules (Dart name, `required T` or `Optional<T?>`, doc comment) shared by input objects and, later, variables. `InputObjectEmitter` writes a final class (`RegularInputEmitter`) or, for `@oneOf`, a sealed class with one variant per field (`OneOfInputEmitter`), each with a reader and `toJson` (R7.7). `DartWriter` gains `fits`, `assign`, `arrow` and `arrowJoined` for lines that wrap at 80 columns.

Commit on the branch: `3360b1f`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/emit/input_field.dart`, `packages/typed_graphql_codegen/lib/src/emit/input_object_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart`
- Modify: `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`, `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart`
- Test: `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart`, `packages/typed_graphql_codegen/test/emit/input_field_test.dart`, `packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart`

**Interfaces:**
- Consumes: Tasks 1 (`Optional`), 3, 4 (`TypeMapper`).
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// emit/dart_names.dart
  String freeName(String preferred, Iterable<String> taken)

// emit/dart_writer.dart
  bool fits(String text)
  void assign(String head, String expression)
  void arrow(String head, String expression)
  void arrowJoined(String head, List<String> operands, String operator)

// emit/input_field.dart
final class const InputField
  factory InputField.of(InputValue input, TypeMapper mapper, Imports imports)
  factory InputField.exclusive(
  String get fieldType
  bool get holdsList
  String get interpolation
  String get docText
  String get codecName

// emit/input_object_emitter.dart
final class InputObjectEmitter
  const InputObjectEmitter(this.mapper)
  final TypeMapper mapper
  void emit(InputObjectType type, DartWriter writer, Imports imports)

// emit/one_of_input_emitter.dart
final class OneOfInputEmitter
  const OneOfInputEmitter(this.mapper)
  final TypeMapper mapper
  void emit(

// emit/regular_input_emitter.dart
final class RegularInputEmitter
  const RegularInputEmitter(this.mapper)
  final TypeMapper mapper
  void emit(
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -73,4 +73,40 @@ void main() {
   test('text of an empty writer is empty', () {
     expect(DartWriter().text, '');
   });
+
+  test('assign stays on one line when it fits', () {
+    final DartWriter writer = DartWriter();
+    writer.assign('final x', 'f(1)');
+    expect(writer.text, 'final x = f(1);\n');
+  });
+
+  test('assign breaks after the equals sign when that fits', () {
+    final DartWriter writer = DartWriter();
+    final String call = 'f(${'a' * 70})';
+    writer.assign('final x', call);
+    expect(writer.text, 'final x =\n    $call;\n');
+  });
+
+  test('arrow breaks a long call into its arguments', () {
+    final DartWriter writer = DartWriter();
+    final String inner = 'g(${'a' * 70})';
+    writer.arrow('int get x', 'f($inner)');
+    expect(writer.text, 'int get x => f(\n  $inner,\n);\n');
+  });
+
+  test('arrowJoined puts one operand per line when it is too long', () {
+    final DartWriter writer = DartWriter();
+    final String operand = 'a' * 40;
+    writer.arrowJoined('bool get x', <String>[operand, operand], '&&');
+    expect(
+      writer.text,
+      'bool get x =>\n    $operand &&\n    $operand;\n',
+    );
+  });
+
+  test('arrowJoined joins the operands on one line when they fit', () {
+    final DartWriter writer = DartWriter();
+    writer.arrowJoined('bool get x', <String>['a', 'b'], '&&');
+    expect(writer.text, 'bool get x => a && b;\n');
+  });
 }
```

Create `packages/typed_graphql_codegen/test/emit/input_field_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_type.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/input_field.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';

void main() {
  InputField field(String sdl, {bool isExclusive = false}) {
    final document = const Parser()
        .parse(Source('enum Role { A }\ninput Probe { $sdl }'))
        .requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    final input = (schema.typeNamed('Probe')! as InputObjectType).fields.first;
    final mapper = TypeMapper(schema, const {});
    return isExclusive
        ? InputField.exclusive(input, mapper, Imports())
        : InputField.of(input, mapper, Imports());
  }

  test('a non-null field without a default is required', () {
    final InputField result = field('a: Int!');
    expect(result.isOptional, false);
    expect(result.fieldType, 'int');
    expect(result.doc, 'The field `a`.');
  });

  test('a nullable field is optional with a nullable value', () {
    final InputField result = field('a: Int');
    expect(result.isOptional, true);
    expect(result.fieldType, 'graphql.Optional<int?>');
    expect(
      result.value,
      const DartType(
        'int?',
        'client.NullableDataCodec(client.ScalarDataCodec(graphql.IntCodec()))',
      ),
    );
  });

  test('a non-null field with a default is optional with a non-null value', () {
    final InputField result = field('a: [Int!]! = [1, 2]');
    expect(result.isOptional, true);
    expect(result.fieldType, 'graphql.Optional<List<int>>');
    expect(result.doc, 'The field `a`. Its default is `[1, 2]`.');
  });

  test('a description, a default and a deprecation are all kept', () {
    final InputField result = field(
      '"Says it." a: Role = A @deprecated(reason: "Use b.")',
    );
    expect(
      result.doc,
      'Says it. Its default is `A`.\n\nDeprecated: Use b.',
    );
  });

  test('a name that is a reserved word gets a dollar', () {
    expect(field('default: Int').dartName, r'default$');
    expect(field('codec: Int').dartName, r'codec$');
  });

  test('a list value is found for equality, a named type is not', () {
    expect(field('a: [Int]').holdsList, true);
    expect(field('a: Role').holdsList, false);
  });

  test('an interpolation of a name with a dollar uses braces', () {
    expect(field('default: Int').interpolation, r'${default$}');
    expect(field('a: Int').interpolation, r'$a');
  });

  test('an exclusive field is given and has the non-null type', () {
    final InputField result = field('a: Int', isExclusive: true);
    expect(result.isOptional, false);
    expect(result.fieldType, 'int');
  });
}
```

Create `packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart`:

````dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/input_object_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';

void main() {
  String emit(String sdl, String name) {
    final document = const Parser().parse(Source(sdl)).requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    final DartWriter writer = DartWriter();
    InputObjectEmitter(
      TypeMapper(schema, const {}),
    ).emit(schema.typeNamed(name)! as InputObjectType, writer, Imports());
    return writer.text;
  }

  test('a regular input object with every kind of field', () {
    expect(
      emit('''
enum Role { ADMIN }
input UserFilter {
  role: Role
  name: String = "x"
  limit: Int! = 10
  ids: [ID!]!
  tags: [String!]
  nested: UserFilter
}
''', 'UserFilter'),
      r'''
/// The input object `UserFilter`.
final class UserFilter implements client.DataObject {
  /// Creates the input object.
  const UserFilter({
    required this.ids,
    this.role = const graphql.Optional.absent(),
    this.name = const graphql.Optional.absent(),
    this.limit = const graphql.Optional.absent(),
    this.tags = const graphql.Optional.absent(),
    this.nested = const graphql.Optional.absent(),
  });

  factory UserFilter._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => UserFilter(
    role: _roleCodec.optionalField(json, 'role', context),
    name: _nameCodec.optionalField(json, 'name', context),
    limit: _limitCodec.optionalField(json, 'limit', context),
    ids: _idsCodec.field(json, 'ids', context),
    tags: _tagsCodec.optionalField(json, 'tags', context),
    nested: _nestedCodec.optionalField(json, 'nested', context),
  );

  /// Reads and writes the values of `UserFilter`.
  static const client.DataCodec<UserFilter> codec =
      client.ObjectDataCodec(UserFilter._read);

  static const client.DataCodec<Role?> _roleCodec =
      client.NullableDataCodec(Role.codec);

  static const client.DataCodec<String?> _nameCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  static const client.DataCodec<int> _limitCodec =
      client.ScalarDataCodec(graphql.IntCodec());

  static const client.DataCodec<List<String>> _idsCodec =
      client.ListDataCodec(client.ScalarDataCodec(graphql.IdCodec()));

  static const client.DataCodec<List<String>?> _tagsCodec =
      client.NullableDataCodec(
        client.ListDataCodec(client.ScalarDataCodec(graphql.StringCodec())),
      );

  static const client.DataCodec<UserFilter?> _nestedCodec =
      client.NullableDataCodec(UserFilter.codec);

  /// The field `role`.
  final graphql.Optional<Role?> role;

  /// The field `name`. Its default is `"x"`.
  final graphql.Optional<String?> name;

  /// The field `limit`. Its default is `10`.
  final graphql.Optional<int> limit;

  /// The field `ids`.
  final List<String> ids;

  /// The field `tags`.
  final graphql.Optional<List<String>?> tags;

  /// The field `nested`.
  final graphql.Optional<UserFilter?> nested;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    if (role case graphql.Present(:final value))
      'role': _roleCodec.write(value),
    if (name case graphql.Present(:final value))
      'name': _nameCodec.write(value),
    if (limit case graphql.Present(:final value))
      'limit': _limitCodec.write(value),
    'ids': _idsCodec.write(ids),
    if (tags case graphql.Present(:final value))
      'tags': _tagsCodec.write(value),
    if (nested case graphql.Present(:final value))
      'nested': _nestedCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is UserFilter &&
      other.role == role &&
      other.name == name &&
      other.limit == limit &&
      const client.DataEquality().equals(other.ids, ids) &&
      const client.DataEquality().equals(other.tags, tags) &&
      other.nested == nested;

  @override
  int get hashCode => Object.hashAll([
    role.hashCode,
    name.hashCode,
    limit.hashCode,
    const client.DataEquality().hash(ids),
    const client.DataEquality().hash(tags),
    nested.hashCode,
  ]);

  @override
  String toString() =>
      'UserFilter(role: $role, name: $name, limit: $limit, ids: $ids, '
      'tags: $tags, nested: $nested)';
}
''',
    );
  });

  test('a oneOf input object has a sealed class and a variant per field', () {
    expect(
      emit('''
input Leaf { a: Int }
input SearchBy @oneOf { name: String, id: ID, leaf: Leaf }
''', 'SearchBy'),
      r'''
/// The input object `SearchBy`: exactly one of its fields is given.
sealed class SearchBy implements client.DataObject {
  factory SearchBy._read(graphql.JsonObject json, client.DataContext context) =>
      switch (json.fields.keys.toList()) {
        ['name'] => SearchByName(_nameCodec.field(json, 'name', context)),
        ['id'] => SearchById(_idCodec.field(json, 'id', context)),
        ['leaf'] => SearchByLeaf(_leafCodec.field(json, 'leaf', context)),
        _ => throw const client.DataFormatException(
          'Expected exactly one of the fields name, id, leaf.',
        ),
      };

  /// Reads and writes the values of `SearchBy`.
  static const client.DataCodec<SearchBy> codec =
      client.ObjectDataCodec(SearchBy._read);

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<Leaf> _leafCodec = Leaf.codec;
}

/// [SearchBy] with its field `name`.
final class SearchByName implements SearchBy {
  /// Creates the input object with its field `name`.
  const SearchByName(this.name);

  /// The field `name`.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'name': SearchBy._nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) => other is SearchByName && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'SearchByName($name)';
}

/// [SearchBy] with its field `id`.
final class SearchById implements SearchBy {
  /// Creates the input object with its field `id`.
  const SearchById(this.id);

  /// The field `id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': SearchBy._idCodec.write(id),
  });

  @override
  bool operator ==(Object other) => other is SearchById && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SearchById($id)';
}

/// [SearchBy] with its field `leaf`.
final class SearchByLeaf implements SearchBy {
  /// Creates the input object with its field `leaf`.
  const SearchByLeaf(this.leaf);

  /// The field `leaf`.
  final Leaf leaf;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'leaf': SearchBy._leafCodec.write(leaf),
  });

  @override
  bool operator ==(Object other) => other is SearchByLeaf && other.leaf == leaf;

  @override
  int get hashCode => leaf.hashCode;

  @override
  String toString() => 'SearchByLeaf($leaf)';
}
''',
    );
  });

  test('names that need a dollar and a field named other', () {
    expect(
      emit('''
input Odd {
  default: Int!
  _id: ID
  other: [Int!]
}
''', 'Odd'),
      r'''
/// The input object `Odd`.
final class Odd implements client.DataObject {
  /// Creates the input object.
  const Odd({
    required this.default$,
    this.$id = const graphql.Optional.absent(),
    this.other = const graphql.Optional.absent(),
  });

  factory Odd._read(graphql.JsonObject json, client.DataContext context) =>
      Odd(
        default$: _default$Codec.field(json, 'default', context),
        $id: _$idCodec.optionalField(json, '_id', context),
        other: _otherCodec.optionalField(json, 'other', context),
      );

  /// Reads and writes the values of `Odd`.
  static const client.DataCodec<Odd> codec = client.ObjectDataCodec(Odd._read);

  static const client.DataCodec<int> _default$Codec =
      client.ScalarDataCodec(graphql.IntCodec());

  static const client.DataCodec<String?> _$idCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.IdCodec()));

  static const client.DataCodec<List<int>?> _otherCodec =
      client.NullableDataCodec(
        client.ListDataCodec(client.ScalarDataCodec(graphql.IntCodec())),
      );

  /// The field `default`.
  final int default$;

  /// The field `_id`.
  final graphql.Optional<String?> $id;

  /// The field `other`.
  final graphql.Optional<List<int>?> other;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'default': _default$Codec.write(default$),
    if ($id case graphql.Present(:final value)) '_id': _$idCodec.write(value),
    if (other case graphql.Present(:final value))
      'other': _otherCodec.write(value),
  });

  @override
  bool operator ==(Object other$) =>
      other$ is Odd &&
      other$.default$ == default$ &&
      other$.$id == $id &&
      const client.DataEquality().equals(other$.other, other);

  @override
  int get hashCode => Object.hashAll([
    default$.hashCode,
    $id.hashCode,
    const client.DataEquality().hash(other),
  ]);

  @override
  String toString() =>
      'Odd(default\$: ${default$}, \$id: ${$id}, other: $other)';
}
''',
    );
  });

  test('a deprecated field and a described type with a code fence', () {
    expect(
      emit('''
"""
Odd names.

```
code
```
"""
input Doc {
  "Field doc."
  old: String @deprecated(reason: "Use x.")
  plain: String @deprecated
}
''', 'Doc'),
      r'''
/// Odd names.
///
/// ```text
/// code
/// ```
final class Doc implements client.DataObject {
  /// Creates the input object.
  const Doc({
    this.old = const graphql.Optional.absent(),
    this.plain = const graphql.Optional.absent(),
  });

  factory Doc._read(graphql.JsonObject json, client.DataContext context) =>
      Doc(
        old: _oldCodec.optionalField(json, 'old', context),
        plain: _plainCodec.optionalField(json, 'plain', context),
      );

  /// Reads and writes the values of `Doc`.
  static const client.DataCodec<Doc> codec = client.ObjectDataCodec(Doc._read);

  static const client.DataCodec<String?> _oldCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  static const client.DataCodec<String?> _plainCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  /// Field doc.
  ///
  /// Deprecated: Use x.
  final graphql.Optional<String?> old;

  /// The field `plain`.
  ///
  /// Deprecated: No longer supported
  final graphql.Optional<String?> plain;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    if (old case graphql.Present(:final value)) 'old': _oldCodec.write(value),
    if (plain case graphql.Present(:final value))
      'plain': _plainCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is Doc &&
      other.old == old &&
      other.plain == plain;

  @override
  int get hashCode => Object.hashAll([old.hashCode, plain.hashCode]);

  @override
  String toString() => 'Doc(old: $old, plain: $plain)';
}
''',
    );
  });
}
````

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/dart_writer_test.dart test/emit/input_field_test.dart test/emit/input_object_emitter_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -110,6 +110,16 @@ final class DartNames {
     return result;
   }
 
+  /// [preferred], or the first of it with `$` appended until it is not in
+  /// [taken]: a parameter name that cannot hide a member.
+  String freeName(String preferred, Iterable<String> taken) {
+    int count = 0;
+    while (taken.contains('$preferred${r'$' * count}')) {
+      count++;
+    }
+    return '$preferred${r'$' * count}';
+  }
+
   /// [memberName] with its first character upper-cased, `$` kept.
   String capitalized(String memberName) => _upperFirst(memberName);
 
```

In `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -82,6 +82,91 @@ final class DartWriter {
     line(close);
   }
 
+  /// Whether [text] written as one line at the current indentation stays
+  /// within 80 columns.
+  bool fits(String text) => _indentation.length + text.length <= _maxColumns;
+
+  /// Writes `head = expression;`, breaking after the `=` when it is too long.
+  void assign(String head, String expression) =>
+      _continued(head, '=', expression);
+
+  /// Writes `head => expression;`, breaking after the `=>` when it is too
+  /// long.
+  void arrow(String head, String expression) =>
+      _continued(head, '=>', expression);
+
+  /// Writes `head => a op b op c;` on one line when it fits, otherwise
+  /// `head =>` and one operand per line, each but the last ending with
+  /// [operator].
+  void arrowJoined(String head, List<String> operands, String operator) {
+    final String single = '$head => ${operands.join(' $operator ')};';
+    if (fits(single)) {
+      line(single);
+      return;
+    }
+    line('$head =>');
+    indented(() {
+      indented(() {
+        for (final (int index, String operand) in operands.indexed) {
+          final bool isLast = index == operands.length - 1;
+          line(isLast ? '$operand;' : '$operand $operator');
+        }
+      });
+    });
+  }
+
+  void _continued(String head, String operator, String expression) {
+    final String single = '$head $operator $expression;';
+    if (fits(single)) {
+      line(single);
+      return;
+    }
+    if (_fitsAfterBreak(expression) ||
+        !expression.endsWith(')') ||
+        !expression.contains('(')) {
+      line('$head $operator');
+      indented(() => indented(() => line('$expression;')));
+      return;
+    }
+    final int open = expression.indexOf('(');
+    final String opening = expression.substring(0, open + 1);
+    final String inner = expression.substring(open + 1, expression.length - 1);
+    if (fits('$head $operator $opening')) {
+      line('$head $operator $opening');
+      indented(() => _breakCall(inner));
+      line(');');
+      return;
+    }
+    line('$head $operator');
+    indented(() {
+      indented(() {
+        line(opening);
+        indented(() => _breakCall(inner));
+        line(');');
+      });
+    });
+  }
+
+  bool _fitsAfterBreak(String expression) {
+    _level += 2;
+    final bool result = fits('$expression;');
+    _level -= 2;
+    return result;
+  }
+
+  // Writes the argument [text] of a call, breaking nested single-argument
+  // calls until each line fits.
+  void _breakCall(String text) {
+    final int open = text.indexOf('(');
+    if (fits('$text,') || open < 0 || !text.endsWith(')')) {
+      line('$text,');
+      return;
+    }
+    line(text.substring(0, open + 1));
+    indented(() => _breakCall(text.substring(open + 1, text.length - 1)));
+    line('),');
+  }
+
   /// Everything written; ends with exactly one line break.
   String get text {
     final String written = _buffer.toString().trimRight();
```

Create `packages/typed_graphql_codegen/lib/src/emit/input_field.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_type.dart';
import 'imports.dart';
import 'type_mapper.dart';

/// The plan of one input field, or one operation variable: its names, its
/// Dart type and whether the caller may leave it out (spec §7 "Input objects
/// and variables", R7.7).
///
/// {@category codegen}
final class const InputField({
  /// The name in GraphQL.
  required final String graphQLName,

  /// The Dart member name.
  required final String dartName,

  /// The Dart type of the value, without `Optional`.
  required final DartType value,

  /// Whether the field is an `Optional`, absent unless the caller gives it.
  required final bool isOptional,

  /// The doc comment text; null for the default.
  final String? doc,
}) {
  /// Creates a field plan.
  this;

  /// The plan of [input]: a nullable field, or one with a default, is
  /// optional.
  factory InputField.of(InputValue input, TypeMapper mapper, Imports imports) {
    final DartType type = mapper.of(input.type, imports);
    return InputField(
      graphQLName: input.name,
      dartName: _name(input.name),
      value: type,
      isOptional: input.type is! NonNullType || input.defaultValue != null,
      doc: _doc(input),
    );
  }

  /// The plan of a field of a `@oneOf` input object: always given, with the
  /// non-null type, because the variant that holds it says which is given.
  factory InputField.exclusive(
    InputValue input,
    TypeMapper mapper,
    Imports imports,
  ) => InputField(
    graphQLName: input.name,
    dartName: _name(input.name),
    value: mapper.ofNonNull(input.type, imports),
    isOptional: false,
    doc: _doc(input),
  );

  /// The type of the Dart field: `graphql.Optional<T>` or the value type.
  String get fieldType =>
      isOptional ? 'graphql.Optional<${value.type}>' : value.type;

  /// Whether the value type holds a list, so equality must compare items.
  bool get holdsList => _list.hasMatch(value.type);

  /// The member read inside a string literal: `$name`, or `${name}` when the
  /// name has a `$` that would end the short form early.
  String get interpolation =>
      dartName.contains(r'$') ? '\${$dartName}' : '\$$dartName';

  /// The text of [doc], or the default for the field.
  String get docText => doc ?? 'The field `$graphQLName`.';

  /// The private codec field, `_<dartName>Codec`.
  String get codecName => '_${dartName}Codec';

  static final RegExp _list = RegExp(r'(^|[^\w$.])List<');

  static String _name(String name) => const DartNames().memberName(
    name,
    reservedMembers: DartNames.objectMembers,
  );

  static String _doc(InputValue input) {
    final String base = input.description ?? 'The field `${input.name}`.';
    final StringBuffer out = StringBuffer(base);
    final Value? defaultValue = input.defaultValue;
    if (defaultValue != null) {
      final String printed = const Printer()
          .print(defaultValue)
          .replaceAll(RegExp(r'\s*\n\s*'), ' ');
      out
        ..write(base.contains('\n') ? '\n\n' : ' ')
        ..write('Its default is `$printed`.');
    }
    final String? reason = input.deprecationReason;
    if (reason != null) {
      out.write('\n\nDeprecated: $reason');
    }
    return out.toString();
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/input_object_emitter.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'one_of_input_emitter.dart';
import 'regular_input_emitter.dart';
import 'type_mapper.dart';

/// Writes the Dart class of a GraphQL input object (spec §7 "Input objects
/// and variables", R7.7): a final class, or a sealed class with one variant
/// per field for a `@oneOf` input object.
///
/// {@category codegen}
final class InputObjectEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const InputObjectEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  /// Writes the declarations of [type] to [writer], recording imports.
  void emit(InputObjectType type, DartWriter writer, Imports imports) {
    final String name = const DartNames().typeName(type.name);
    if (type.isOneOf) {
      OneOfInputEmitter(mapper).emit(type, name, writer, imports);
    } else {
      RegularInputEmitter(mapper).emit(type, name, writer, imports);
    }
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'input_field.dart';
import 'type_mapper.dart';

/// Writes the classes of a `@oneOf` input object: a sealed class and one
/// variant per field, so the compiler enforces that exactly one is given.
///
/// {@category codegen}
final class OneOfInputEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const OneOfInputEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  static const DartStringLiteral _literal = DartStringLiteral();

  /// Writes the sealed class [name] and its variants for [type] to [writer].
  void emit(
    InputObjectType type,
    String name,
    DartWriter writer,
    Imports imports,
  ) {
    final List<InputField> fields = <InputField>[
      for (final InputValue field in type.fields)
        InputField.exclusive(field, mapper, imports),
    ];
    _writeSealed(type, name, fields, writer);
    for (final InputField field in fields) {
      writer.line();
      _writeVariant(name, field, writer);
    }
  }

  void _writeSealed(
    InputObjectType type,
    String name,
    List<InputField> fields,
    DartWriter writer,
  ) {
    final String? description = type.description;
    writer.doc(
      description == null
          ? 'The input object `${type.name}`: exactly one of its fields is '
                'given.'
          : '$description\n\nExactly one of its fields is given.',
    );
    writer.block('sealed class $name implements client.DataObject', () {
      _writeReader(name, fields, writer);
      writer
        ..line()
        ..doc('Reads and writes the values of `${type.name}`.')
        ..assign(
          'static const client.DataCodec<$name> codec',
          'client.ObjectDataCodec($name._read)',
        );
      for (final InputField field in fields) {
        writer
          ..line()
          ..assign(
            'static const client.DataCodec<${field.value.type}> '
            '${field.codecName}',
            field.value.codec,
          );
      }
    });
  }

  void _writeReader(String name, List<InputField> fields, DartWriter writer) {
    final String names = fields.map((f) => f.graphQLName).join(', ');
    const String parameters =
        'graphql.JsonObject json, client.DataContext context';
    final String header = 'factory $name._read($parameters) =>';
    if (writer.fits(header)) {
      writer.line(header);
    } else {
      writer
        ..line('factory $name._read(')
        ..indented(() {
          writer
            ..line('graphql.JsonObject json,')
            ..line('client.DataContext context,');
        })
        ..line(') =>');
    }
    writer.indented(
      () => writer.indented(() {
        writer.line('switch (json.fields.keys.toList()) {');
        writer.indented(() {
          for (final InputField field in fields) {
            _writeArm(name, field, writer);
          }
          writer
            ..line('_ => throw const client.DataFormatException(')
            ..indented(() {
              writer.line(
                '${_literal.of('Expected exactly one of the fields $names.')},',
              );
            })
            ..line('),');
        });
        writer.line('};');
      }),
    );
  }

  void _writeArm(String name, InputField field, DartWriter writer) {
    final String variant = '$name${_names.capitalized(field.dartName)}';
    final String arm = '[${_literal.of(field.graphQLName)}] =>';
    final String value =
        '$variant(${field.codecName}.field(json, '
        '${_literal.of(field.graphQLName)}, context)),';
    if (writer.fits('$arm $value')) {
      writer.line('$arm $value');
    } else {
      writer.line(arm);
      writer.indented(() => writer.line(value));
    }
  }

  static const DartNames _names = DartNames();

  void _writeVariant(String base, InputField field, DartWriter writer) {
    final String variant = '$base${_names.capitalized(field.dartName)}';
    final String escaped = variant.replaceAll(r'$', r'\$');
    final String name = field.dartName;
    writer
      ..doc('[$base] with its field `${field.graphQLName}`.')
      ..block('final class $variant implements $base', () {
        writer
          ..doc(
            'Creates the input object with its field `${field.graphQLName}`.',
          )
          ..line('const $variant(this.$name);')
          ..line()
          ..doc(field.docText)
          ..line('final ${field.value.type} $name;')
          ..line()
          ..line('@override')
          ..line('graphql.JsonObject toJson() => graphql.JsonObject({')
          ..indented(() {
            writer.line(
              '${_literal.of(field.graphQLName)}: '
              '$base.${field.codecName}.write($name),',
            );
          })
          ..line('});')
          ..line();
        _writeEquality(variant, name, writer);
        writer
          ..line()
          ..line('@override')
          ..arrow('String toString()', "'$escaped(${field.interpolation})'");
      });
  }

  void _writeEquality(String variant, String name, DartWriter writer) {
    final String other = _names.freeName('other', <String>[name]);
    writer
      ..line('@override')
      ..arrow(
        'bool operator ==(Object $other)',
        '$other is $variant && $other.$name == $name',
      )
      ..line()
      ..line('@override')
      ..line('int get hashCode => $name.hashCode;');
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'dart_names.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'input_field.dart';
import 'type_mapper.dart';

/// Writes the class of an input object that is not `@oneOf`.
///
/// {@category codegen}
final class RegularInputEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const RegularInputEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  static const DartStringLiteral _literal = DartStringLiteral();

  /// Writes the class [name] for [type] to [writer].
  void emit(
    InputObjectType type,
    String name,
    DartWriter writer,
    Imports imports,
  ) {
    final List<InputField> fields = <InputField>[
      for (final InputValue field in type.fields)
        InputField.of(field, mapper, imports),
    ];
    writer
      ..doc(type.description ?? 'The input object `${type.name}`.')
      ..block('final class $name implements client.DataObject', () {
        _writeConstructor(name, fields, writer);
        writer.line();
        _writeReader(name, fields, writer);
        _writeDeclarations(type, name, fields, writer);
        _writeToJson(fields, writer);
        writer.line();
        _writeEquality(name, fields, writer);
        writer.line();
        _writeToString(name, fields, writer);
      });
  }

  void _writeDeclarations(
    InputObjectType type,
    String name,
    List<InputField> fields,
    DartWriter writer,
  ) {
    writer
      ..line()
      ..doc('Reads and writes the values of `${type.name}`.')
      ..assign(
        'static const client.DataCodec<$name> codec',
        'client.ObjectDataCodec($name._read)',
      )
      ..line();
    for (final InputField field in fields) {
      writer
        ..assign(
          'static const client.DataCodec<${field.value.type}> '
          '${field.codecName}',
          field.value.codec,
        )
        ..line();
    }
    for (final InputField field in fields) {
      writer
        ..doc(field.docText)
        ..line('final ${field.fieldType} ${field.dartName};')
        ..line();
    }
  }

  void _writeConstructor(
    String name,
    List<InputField> fields,
    DartWriter writer,
  ) {
    final List<String> parameters = <String>[
      for (final InputField field in fields)
        if (!field.isOptional) 'required this.${field.dartName}',
      for (final InputField field in fields)
        if (field.isOptional)
          'this.${field.dartName} = const graphql.Optional.absent()',
    ];
    writer
      ..doc('Creates the input object.')
      ..items('const $name({', parameters, '});');
  }

  void _writeReader(String name, List<InputField> fields, DartWriter writer) {
    final List<String> arguments = <String>[
      for (final InputField field in fields)
        '${field.dartName}: ${field.codecName}.'
            '${field.isOptional ? 'optionalField' : 'field'}'
            '(json, ${_literal.of(field.graphQLName)}, context)',
    ];
    const String parameters =
        'graphql.JsonObject json, client.DataContext context';
    if (writer.fits('factory $name._read($parameters) =>')) {
      writer.line('factory $name._read($parameters) =>');
      writer.indented(
        () => writer.indented(
          () => _writeConstruction(name, arguments, writer),
        ),
      );
      return;
    }
    writer
      ..line('factory $name._read(')
      ..indented(() {
        writer
          ..line('graphql.JsonObject json,')
          ..line('client.DataContext context,');
      })
      ..line(') => $name(');
    writer
      ..indented(() {
        for (final String argument in arguments) {
          writer.line('$argument,');
        }
      })
      ..line(');');
  }

  void _writeConstruction(
    String name,
    List<String> arguments,
    DartWriter writer,
  ) {
    writer.line('$name(');
    writer.indented(() {
      for (final String argument in arguments) {
        writer.line('$argument,');
      }
    });
    writer.line(');');
  }

  void _writeToJson(List<InputField> fields, DartWriter writer) {
    writer
      ..line('@override')
      ..line('graphql.JsonObject toJson() => graphql.JsonObject({')
      ..indented(() {
        for (final InputField field in fields) {
          final String key = _literal.of(field.graphQLName);
          final String write = '$key: ${field.codecName}.write';
          if (!field.isOptional) {
            writer.line('$write(${field.dartName}),');
            continue;
          }
          final String test =
              'if (${field.dartName} case '
              'graphql.Present(:final value))';
          final String entry = '$write(value),';
          if (writer.fits('$test $entry')) {
            writer.line('$test $entry');
          } else {
            writer.line(test);
            writer.indented(() => writer.line(entry));
          }
        }
      })
      ..line('});');
  }

  void _writeEquality(String name, List<InputField> fields, DartWriter writer) {
    final String other = const DartNames().freeName('other', <String>[
      for (final InputField field in fields) field.dartName,
    ]);
    writer
      ..line('@override')
      ..arrowJoined('bool operator ==(Object $other)', <String>[
        '$other is $name',
        for (final InputField field in fields)
          if (field.holdsList)
            'const client.DataEquality().equals($other.${field.dartName}, '
                '${field.dartName})'
          else
            '$other.${field.dartName} == ${field.dartName}',
      ], '&&')
      ..line()
      ..line('@override');
    final List<String> hashes = <String>[
      for (final InputField field in fields)
        if (field.holdsList)
          'const client.DataEquality().hash(${field.dartName})'
        else
          '${field.dartName}.hashCode',
    ];
    if (hashes.length == 1) {
      writer.arrow('int get hashCode', hashes.single);
    } else {
      writer.items('int get hashCode => Object.hashAll([', hashes, ']);');
    }
  }

  void _writeToString(String name, List<InputField> fields, DartWriter writer) {
    final String escaped = name.replaceAll(r'$', r'\$');
    final List<String> tokens = <String>[
      for (final InputField field in fields)
        '${field.dartName.replaceAll(r'$', r'\$')}: ${field.interpolation}',
    ];
    writer.line('@override');
    final String single = "'$escaped(${tokens.join(', ')})'";
    if (writer.fits('String toString() => $single;')) {
      writer.line('String toString() => $single;');
      return;
    }
    writer.line('String toString() =>');
    writer.indented(() {
      writer.indented(() => _writeSplitLiteral(escaped, tokens, writer));
    });
  }

  void _writeSplitLiteral(String name, List<String> tokens, DartWriter writer) {
    StringBuffer current = StringBuffer('$name(');
    final List<String> lines = <String>[];
    for (final (int index, String token) in tokens.indexed) {
      final String piece = '$token${index == tokens.length - 1 ? ')' : ', '}';
      if (!writer.fits("'$current$piece';") && current.isNotEmpty) {
        lines.add('$current');
        current = StringBuffer();
      }
      current.write(piece);
    }
    lines.add('$current');
    for (final (int index, String text) in lines.indexed) {
      writer.line("'$text'${index == lines.length - 1 ? ';' : ''}");
    }
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/dart_writer_test.dart test/emit/input_field_test.dart test/emit/input_object_emitter_test.dart)
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
git add packages/typed_graphql_codegen/lib/src/emit/dart_names.dart packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart packages/typed_graphql_codegen/lib/src/emit/input_field.dart packages/typed_graphql_codegen/lib/src/emit/input_object_emitter.dart packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart packages/typed_graphql_codegen/test/emit/dart_writer_test.dart packages/typed_graphql_codegen/test/emit/input_field_test.dart packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart
git commit -q -m "feat(typed_graphql_codegen): emit input objects" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Add the generated-name diagnostic codes GQL507 and GQL508

The core catalog gains `GQL507` generatedNameCollision (a Dart name the generator would declare twice) and `GQL508` reservedTypeName (a name that hides a Dart type the generated code uses), in their own commit before Task 7 reports them.

Commit on the branch: `4643be0`.

**Files:**
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: The core `DiagnosticCode`.
- Produces:
- Diagnostic codes: `GQL507`, `GQL508`.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -538,4 +538,14 @@ enum DiagnosticCode(
   /// `GQL506`: no document matches the configuration's `documents`; reported
   /// as a warning.
   noDocuments('GQL506'),
+
+  /// `GQL507`: the code generator would declare one Dart name twice, such as
+  /// an enum `Role` and an input object `RoleKnown`; reported at the second
+  /// declaration, related to the first.
+  generatedNameCollision('GQL507'),
+
+  /// `GQL508`: a name the code generator would declare hides a Dart type the
+  /// generated code uses, such as `List` or a `dart:core` type a scalar is
+  /// mapped to.
+  reservedTypeName('GQL508'),
 }
```

- [ ] **Step 2: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The catalog adds `GQL507` (a Dart name the code generator would declare
  twice) and `GQL508` (a generated name that hides a Dart type the generated
  code uses).
```

- [ ] **Step 3: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
git commit -q -m "feat(typed_graphql): add the generated-name diagnostic codes GQL507 and GQL508" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Generate the schema-types library

`ClientGenerator.generate` returns a `GenerationResult` and writes the schema-types library: the enums and input objects the documents use (`SchemaTypeUsage`, pruned, transitively through input objects; `SchemaTypesEmitter`). `GeneratedNames` checks every generated name before any file is written (`GQL507`, `GQL508`). The golden harness (`golden_test.dart`, `GoldenCase`) and the analysis test (`generated_code_test.dart`, `GeneratedPackage`) compile, analyze and run the generated code of two cases in a temporary package (R7.10).

Commit on the branch: `905f203`.

**Files:**
- Create: `packages/typed_graphql_codegen/dart_test.yaml`, `packages/typed_graphql_codegen/lib/src/emit/schema_types_emitter.dart`, `packages/typed_graphql_codegen/lib/src/generator/generated_file.dart`, `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart`, `packages/typed_graphql_codegen/lib/src/generator/generation_result.dart`, `packages/typed_graphql_codegen/lib/src/generator/schema_type_usage.dart`
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/README.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`, `packages/typed_graphql_codegen/lib/src/emit/input_field.dart`, `packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart`, `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`
- Test: `packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart`, `packages/typed_graphql_codegen/test/generated_code_test.dart`, `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`, `packages/typed_graphql_codegen/test/generator/generated_names_test.dart`, `packages/typed_graphql_codegen/test/generator/schema_type_usage_test.dart`, `packages/typed_graphql_codegen/test/golden_test.dart`, `packages/typed_graphql_codegen/test/goldens/no_documents/input/schema.graphql`, `packages/typed_graphql_codegen/test/goldens/no_documents/input/typed_graphql.yaml`, `packages/typed_graphql_codegen/test/goldens/no_documents/output/lib/schema.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/schema_types/input/lib/user.graphql`, `packages/typed_graphql_codegen/test/goldens/schema_types/input/schema.graphql`, `packages/typed_graphql_codegen/test/goldens/schema_types/input/typed_graphql.yaml`, `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/schema.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/schema_types/support/bin/round_trip.dart.txt`, `packages/typed_graphql_codegen/test/goldens/schema_types/support/packages/scalar_codecs/lib/scalar_codecs.dart.txt`, `packages/typed_graphql_codegen/test/goldens/schema_types/support/packages/scalar_codecs/pubspec.yaml.txt`, `packages/typed_graphql_codegen/test/support/generated_package.dart`, `packages/typed_graphql_codegen/test/support/golden_case.dart`

**Interfaces:**
- Consumes: Tasks 2-6; M10a `ClientGenerator.check`, `ClientProject`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// emit/input_field.dart
  static String dartNameOf(String name)

// emit/schema_types_emitter.dart
final class SchemaTypesEmitter
  const SchemaTypesEmitter(this.mapper)
  final TypeMapper mapper
  String emit(List<SchemaType> types,

// generator/client_generator.dart
  List<Diagnostic> check({
  GenerationResult generate({

// generator/generated_file.dart
final class const GeneratedFile(…)
  int get hashCode
  String toString()

// generator/generated_names.dart
final class GeneratedNames
  GeneratedNames({Iterable<String> mappedCoreTypes = const []})
  List<Diagnostic> get diagnostics
  void register(String name, String declarer, SourceSpan? span)
  void registerSchemaType(SchemaType type)

// generator/generation_result.dart
final class GenerationResult(…)
  bool get hasErrors

// generator/schema_type_usage.dart
final class const SchemaTypeUsage(final Schema schema)
  List<SchemaType> of(Document document)
final class _NamedTypes extends AstVisitor
  VisitAction enter(Node node)
  void leave(Node node)
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -303,11 +303,11 @@ final class Odd implements client.DataObject {
   });
 
   @override
-  bool operator ==(Object other$) =>
-      other$ is Odd &&
-      other$.default$ == default$ &&
-      other$.$id == $id &&
-      const client.DataEquality().equals(other$.other, other);
+  bool operator ==(Object other) =>
+      other is Odd &&
+      other.default$ == default$ &&
+      other.$id == $id &&
+      const client.DataEquality().equals(other.other, this.other);
 
   @override
   int get hashCode => Object.hashAll([
```

Create `packages/typed_graphql_codegen/test/generated_code_test.dart`:

```dart
@TestOn('vm')
@Tags(['analysis'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/generated_package.dart';
import 'support/golden_case.dart';

void main() {
  final workspace = Directory.current.parent.parent.path;
  for (final golden in GoldenCase.all()) {
    group(golden.name, () {
      late Directory package;

      setUp(() {
        package = Directory.systemTemp.createTempSync('generated_');
        GeneratedPackage(package, golden, workspace).write();
      });

      tearDown(() => package.deleteSync(recursive: true));

      test('passes the analyzer and round trips its sample values', () {
        GeneratedPackage.run(package, ['pub', 'get', '--offline']);
        GeneratedPackage.run(package, ['analyze', '--fatal-infos']);
        if (golden.support.containsKey('bin/round_trip.dart')) {
          GeneratedPackage.run(package, ['run', 'bin/round_trip.dart']);
        }
      });
    });
  }
}
```

Create `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
enum Role { ADMIN }

type Query {
  role: Role
}
''');

const _document = ProjectFile('lib/a.graphql', 'query A { role }\n');

void main() {
  CodegenConfig configOf(String text) {
    final result = CodegenConfig.parse(text, path: 'typed_graphql.yaml');
    if (result is! ConfigSuccess) fail('expected success, got $result');
    return result.config;
  }

  final generator = ClientGenerator(configOf('schema: schema.graphql\n'));

  test('writes the schema-types library at the configured path', () {
    final result = generator.generate(
      schema: _schema,
      documents: const [_document],
    );
    expect(
      [for (final file in result.files) file.path],
      [
        'lib/schema.graphql.dart',
      ],
    );
  });

  test('the path follows schema_types', () {
    final result = ClientGenerator(
      configOf('schema: schema.graphql\nschema_types: lib/src/types.dart\n'),
    ).generate(schema: _schema, documents: const [_document]);
    expect(result.files.single.path, 'lib/src/types.dart');
  });

  test('a project with one enum writes that enum', () {
    final result = generator.generate(
      schema: _schema,
      documents: const [_document],
    );
    expect(result.files.single.text, r'''
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
  admin('ADMIN');

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
''');
  });

  test('a project with an error has no files', () {
    final result = generator.generate(
      schema: _schema,
      documents: const [ProjectFile('lib/a.graphql', 'query A { nope }\n')],
    );
    expect(result.hasErrors, isTrue);
    expect(result.files, isEmpty);
  });

  test('a name collision is an error and writes nothing', () {
    final result = generator.generate(
      schema: const ProjectFile('schema.graphql', '''
enum Role { ADMIN }
input RoleKnown { a: Int }

type Query {
  role(by: RoleKnown): Role
}
'''),
      documents: const [
        _document,
        ProjectFile(
          'lib/b.graphql',
          'query B(\$by: RoleKnown) { role(by: \$by) }\n',
        ),
      ],
    );
    expect(result.files, isEmpty);
    expect(result.diagnostics.single.code.id, 'GQL507');
  });

  test('check is the diagnostics of generate', () {
    const documents = [ProjectFile('lib/a.graphql', 'query A { nope }\n')];
    // Each run reads its own sources, so diagnostics compare by text.
    expect(
      [
        for (final d in generator.check(schema: _schema, documents: documents))
          '$d',
      ],
      [
        for (final d
            in generator
                .generate(schema: _schema, documents: documents)
                .diagnostics)
          '$d',
      ],
    );
  });

  test('warnings do not stop the files', () {
    final result = generator.generate(schema: _schema, documents: const []);
    expect(result.hasErrors, isFalse);
    expect(result.diagnostics.single.code.id, 'GQL506');
    expect(result.files, hasLength(1));
  });
}
```

Create `packages/typed_graphql_codegen/test/generator/generated_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/generator/generated_names.dart';

void main() {
  final source = Source('0123456789', name: 'schema.graphql');
  final first = SourceSpan(source, 0, 3);
  final second = SourceSpan(source, 5, 8);

  test('a name declared twice is a GQL507 at the second, related to the first', () {
    final names = GeneratedNames()
      ..register('RoleKnown', "the enum 'Role'", first)
      ..register('RoleKnown', "the input object 'RoleKnown'", second);
    expect(names.diagnostics, [
      Diagnostic(
        .generatedNameCollision,
        .error,
        "The generated name 'RoleKnown' is declared twice: by the enum 'Role' "
        "and by the input object 'RoleKnown'.",
        span: second,
        related: [first],
      ),
    ]);
  });

  test('a collision without spans has none', () {
    final names = GeneratedNames()
      ..register('A', 'the first', null)
      ..register('A', 'the second', null);
    expect(names.diagnostics.single.span, isNull);
    expect(names.diagnostics.single.related, isEmpty);
  });

  test('a reserved name is a GQL508 at its declaration', () {
    final names = GeneratedNames()..register('List', "the enum 'List'", first);
    expect(names.diagnostics, [
      Diagnostic(
        .reservedTypeName,
        .error,
        "The generated name 'List' would hide the Dart type 'List' the "
        'generated code uses.',
        span: first,
      ),
    ]);
  });

  test('a dart:core type a scalar is mapped to is reserved', () {
    final names = GeneratedNames(mappedCoreTypes: ['Rational'])
      ..register('Rational', "the enum 'Rational'", null);
    expect(names.diagnostics.single.code, DiagnosticCode.reservedTypeName);
  });

  test('distinct ordinary names are fine', () {
    final names = GeneratedNames()
      ..register('Role', "the enum 'Role'", first)
      ..register('Other', "the enum 'Other'", second);
    expect(names.diagnostics, isEmpty);
  });

  group('registerSchemaType', () {
    List<String> problems(String sdl) {
      final schema = (const SchemaBuilder().fromSdl(
        const Parser().parse(Source(sdl)).requireDocument(),
      ) as BuildSuccess).schema;
      final names = GeneratedNames();
      schema.types.forEach(names.registerSchemaType);
      return [for (final d in names.diagnostics) d.message];
    }

    test('an enum declares its known and unknown classes', () {
      expect(
        problems('''
enum Role { A }
input RoleKnown { a: Int }
type Query { a: Int }
'''),
        [
          "The generated name 'RoleKnown' is declared twice: by the enum "
              "'Role' and by the input object 'RoleKnown'.",
        ],
      );
    });

    test('a oneOf input declares a class per field', () {
      expect(
        problems('''
input Pick @oneOf { id: ID, name: String }
input PickId { a: Int }
type Query { a: Int }
'''),
        [
          "The generated name 'PickId' is declared twice: by the input object "
              "'Pick' and by the input object 'PickId'.",
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_codegen/test/generator/schema_type_usage_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/generator/schema_type_usage.dart';

const _sdl = '''
enum Role { ADMIN }
enum Color { RED }
enum Unused { A }
input Leaf { color: Color }
input Cycle { next: Cycle, leaf: Leaf }
input Orphan { value: Int }
input Filter { role: Role, more: [Cycle!] }
type User { id: ID!, role: Role!, color: Color }
type Query {
  user(filter: Filter): User
  users: [User!]!
}
''';

void main() {
  List<String> used(String query) {
    final schema = (const SchemaBuilder().fromSdl(
      const Parser().parse(Source(_sdl)).requireDocument(),
    ) as BuildSuccess).schema;
    final document = const Parser().parse(Source(query)).requireDocument();
    return [
      for (final type in SchemaTypeUsage(schema).of(document)) type.name,
    ];
  }

  test('a variable reaches its input object and what that holds', () {
    expect(used(r'query Q($f: Filter) { users { id } }'), [
      'Color',
      'Cycle',
      'Filter',
      'Leaf',
      'Role',
    ]);
  });

  test('a selected field reaches its enum', () {
    expect(used('query Q { users { role } }'), ['Role']);
  });

  test('a fragment field reaches its enum', () {
    expect(used('fragment F on User { color }'), ['Color']);
  });

  test('a type no variable or field reaches is absent', () {
    expect(used(r'query Q($f: Leaf) { users { id } }'), ['Color', 'Leaf']);
  });

  test('an input object that refers to itself is listed once', () {
    expect(used(r'query Q($c: Cycle!) { users { id } }'), [
      'Color',
      'Cycle',
      'Leaf',
    ]);
  });

  test('a document with no variables and only scalar fields uses nothing', () {
    expect(used('query Q { users { id } }'), isEmpty);
  });
}
```

Create `packages/typed_graphql_codegen/test/golden_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

import 'support/golden_case.dart';

void main() {
  final update = Platform.environment['UPDATE_GOLDENS'] == '1';
  for (final golden in GoldenCase.all()) {
    group(golden.name, () {
      final result = ClientGenerator(
        golden.config,
      ).generate(schema: golden.schema, documents: golden.documents);
      if (update) golden.writeGoldens(result.files);

      test('generates without errors', () {
        expect(result.hasErrors, isFalse, reason: '${result.diagnostics}');
      });

      test('writes the files of the goldens', () {
        expect([
          for (final file in result.files) file.path,
        ], golden.goldens.keys.toList()..sort());
      });

      for (final file in result.files) {
        test('${file.path} equals its golden', () {
          expect(file.text, golden.goldens[file.path]);
        });
      }
    });
  }
}
```

Create `packages/typed_graphql_codegen/test/goldens/no_documents/input/schema.graphql`:

```graphql
type Query {
  hello: String
}
```

Create `packages/typed_graphql_codegen/test/goldens/no_documents/input/typed_graphql.yaml`:

```yaml
schema: schema.graphql
```

Create `packages/typed_graphql_codegen/test/goldens/no_documents/output/lib/schema.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from schema.graphql.
// dart format off
```

Create `packages/typed_graphql_codegen/test/goldens/schema_types/input/lib/user.graphql`:

```graphql
query GetUser($id: ID!, $withFriends: Boolean = false, $full: Boolean!) {
  user(id: $id) {
    ...UserCard @include(if: $full)
    role
    createdAt
    cursor
    friends(first: 2) @include(if: $withFriends) {
      id
      name
    }
  }
}

fragment UserCard on User {
  id
  name
}

query Search($by: SearchBy!, $filter: UserFilter, $paging: Paging) {
  search(by: $by, filter: $filter, paging: $paging) {
    __typename
  }
}
```

Create `packages/typed_graphql_codegen/test/goldens/schema_types/input/schema.graphql`:

```graphql
"A user role."
enum Role {
  ADMIN
  EDITOR
  VIEWER @deprecated(reason: "Use EDITOR.")
}

enum Unused {
  A
}

scalar DateTime

scalar Cursor

input UserFilter {
  role: Role
  name: String = "x"
  ids: [ID!]!
  nested: UserFilter
  since: DateTime
}

input SearchBy @oneOf {
  name: String
  id: ID
}

"Names that Dart reserves or that the generated class already has."
input Paging {
  default: Int
  other: String!
  after: Cursor
}

input Unreached {
  value: Int
}

interface Node {
  id: ID!
}

type User implements Node {
  id: ID!
  name: String!
  role: Role!
  createdAt: DateTime
  cursor: Cursor
  friends(first: Int): [User!]!
}

type Bot implements Node {
  id: ID!
  model: String
}

union SearchResult = User | Bot

type Query {
  user(id: ID!): User
  node(id: ID!): Node
  search(by: SearchBy!, filter: UserFilter, paging: Paging): [SearchResult!]!
}
```

Create `packages/typed_graphql_codegen/test/goldens/schema_types/input/typed_graphql.yaml`:

```yaml
schema: schema.graphql
scalars:
  DateTime:
    type: DateTime
    codec: package:scalar_codecs/scalar_codecs.dart#DateTimeCodec
```

Create `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/schema.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from schema.graphql.
// dart format off

import 'package:scalar_codecs/scalar_codecs.dart' as scalar_0;
import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// Names that Dart reserves or that the generated class already has.
final class Paging implements client.DataObject {
  /// Creates the input object.
  const Paging({
    required this.other,
    this.default$ = const graphql.Optional.absent(),
    this.after = const graphql.Optional.absent(),
  });

  factory Paging._read(graphql.JsonObject json, client.DataContext context) =>
      Paging(
        default$: _default$Codec.optionalField(json, 'default', context),
        other: _otherCodec.field(json, 'other', context),
        after: _afterCodec.optionalField(json, 'after', context),
      );

  /// Reads and writes the values of `Paging`.
  static const client.DataCodec<Paging> codec =
      client.ObjectDataCodec(Paging._read);

  static const client.DataCodec<int?> _default$Codec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.IntCodec()));

  static const client.DataCodec<String> _otherCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<graphql.JsonValue?> _afterCodec =
      client.NullableDataCodec(client.JsonDataCodec());

  /// The field `default`.
  final graphql.Optional<int?> default$;

  /// The field `other`.
  final String other;

  /// The field `after`.
  final graphql.Optional<graphql.JsonValue?> after;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    if (default$ case graphql.Present(:final value))
      'default': _default$Codec.write(value),
    'other': _otherCodec.write(other),
    if (after case graphql.Present(:final value))
      'after': _afterCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is Paging &&
      other.default$ == default$ &&
      other.other == this.other &&
      other.after == after;

  @override
  int get hashCode => Object.hashAll([
    default$.hashCode,
    other.hashCode,
    after.hashCode,
  ]);

  @override
  String toString() =>
      'Paging(default\$: ${default$}, other: $other, after: $after)';
}

/// A user role.
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

  /// `EDITOR`.
  editor('EDITOR'),

  /// `VIEWER`.
  @Deprecated('Use EDITOR.')
  viewer('VIEWER');

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

/// The input object `SearchBy`: exactly one of its fields is given.
sealed class SearchBy implements client.DataObject {
  factory SearchBy._read(graphql.JsonObject json, client.DataContext context) =>
      switch (json.fields.keys.toList()) {
        ['name'] => SearchByName(_nameCodec.field(json, 'name', context)),
        ['id'] => SearchById(_idCodec.field(json, 'id', context)),
        _ => throw const client.DataFormatException(
          'Expected exactly one of the fields name, id.',
        ),
      };

  /// Reads and writes the values of `SearchBy`.
  static const client.DataCodec<SearchBy> codec =
      client.ObjectDataCodec(SearchBy._read);

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());
}

/// [SearchBy] with its field `name`.
final class SearchByName implements SearchBy {
  /// Creates the input object with its field `name`.
  const SearchByName(this.name);

  /// The field `name`.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'name': SearchBy._nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) => other is SearchByName && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'SearchByName($name)';
}

/// [SearchBy] with its field `id`.
final class SearchById implements SearchBy {
  /// Creates the input object with its field `id`.
  const SearchById(this.id);

  /// The field `id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': SearchBy._idCodec.write(id),
  });

  @override
  bool operator ==(Object other) => other is SearchById && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SearchById($id)';
}

/// The input object `UserFilter`.
final class UserFilter implements client.DataObject {
  /// Creates the input object.
  const UserFilter({
    required this.ids,
    this.role = const graphql.Optional.absent(),
    this.name = const graphql.Optional.absent(),
    this.nested = const graphql.Optional.absent(),
    this.since = const graphql.Optional.absent(),
  });

  factory UserFilter._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => UserFilter(
    role: _roleCodec.optionalField(json, 'role', context),
    name: _nameCodec.optionalField(json, 'name', context),
    ids: _idsCodec.field(json, 'ids', context),
    nested: _nestedCodec.optionalField(json, 'nested', context),
    since: _sinceCodec.optionalField(json, 'since', context),
  );

  /// Reads and writes the values of `UserFilter`.
  static const client.DataCodec<UserFilter> codec =
      client.ObjectDataCodec(UserFilter._read);

  static const client.DataCodec<Role?> _roleCodec =
      client.NullableDataCodec(Role.codec);

  static const client.DataCodec<String?> _nameCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  static const client.DataCodec<List<String>> _idsCodec =
      client.ListDataCodec(client.ScalarDataCodec(graphql.IdCodec()));

  static const client.DataCodec<UserFilter?> _nestedCodec =
      client.NullableDataCodec(UserFilter.codec);

  static const client.DataCodec<DateTime?> _sinceCodec =
      client.NullableDataCodec(
        client.ScalarDataCodec(scalar_0.DateTimeCodec()),
      );

  /// The field `role`.
  final graphql.Optional<Role?> role;

  /// The field `name`. Its default is `"x"`.
  final graphql.Optional<String?> name;

  /// The field `ids`.
  final List<String> ids;

  /// The field `nested`.
  final graphql.Optional<UserFilter?> nested;

  /// The field `since`.
  final graphql.Optional<DateTime?> since;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    if (role case graphql.Present(:final value))
      'role': _roleCodec.write(value),
    if (name case graphql.Present(:final value))
      'name': _nameCodec.write(value),
    'ids': _idsCodec.write(ids),
    if (nested case graphql.Present(:final value))
      'nested': _nestedCodec.write(value),
    if (since case graphql.Present(:final value))
      'since': _sinceCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is UserFilter &&
      other.role == role &&
      other.name == name &&
      const client.DataEquality().equals(other.ids, ids) &&
      other.nested == nested &&
      other.since == since;

  @override
  int get hashCode => Object.hashAll([
    role.hashCode,
    name.hashCode,
    const client.DataEquality().hash(ids),
    nested.hashCode,
    since.hashCode,
  ]);

  @override
  String toString() =>
      'UserFilter(role: $role, name: $name, ids: $ids, nested: $nested, '
      'since: $since)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/schema_types/support/bin/round_trip.dart.txt`:

```text
import 'dart:io';

import 'package:generated_schema_types/schema.graphql.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

const DataContext _context = DataContext();

void main() {
  final filter = UserFilter(
    ids: const ['1', '2'],
    role: const Optional.present(RoleKnown.admin),
    name: const Optional.present(null),
    since: Optional.present(DateTime.utc(2026, 10, 15)),
  );
  const paging = Paging(
    other: 'x',
    default$: Optional.present(3),
    after: Optional.present(JsonString('c1')),
  );
  _check('UserFilter', UserFilter.codec, filter);
  _check('Paging', Paging.codec, paging);
  _check('SearchBy', SearchBy.codec, const SearchByName('Ada'));
  _check('SearchBy', SearchBy.codec, const SearchById('7'));
  _check('Role', Role.codec, RoleKnown.editor);
  _check('Role', Role.codec, const RoleUnknown('NEW'));
  if (!paging.toString().contains(r'default$: ')) {
    _fail('Paging.toString is $paging');
  }
}

void _check<T>(String name, DataCodec<T> codec, T value) {
  final T read = codec.read(codec.write(value), _context);
  if (read != value) {
    _fail('$name did not round trip: $value became $read');
  }
}

void _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
```

Create `packages/typed_graphql_codegen/test/goldens/schema_types/support/packages/scalar_codecs/lib/scalar_codecs.dart.txt`:

```text
import 'package:typed_graphql/typed_graphql.dart';

/// Reads and writes a `DateTime` as an ISO 8601 string.
final class const DateTimeCodec() implements ScalarCodec<DateTime> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<DateTime> decode(JsonValue json) => switch (json) {
    JsonString(:final value) when DateTime.tryParse(value) != null =>
      DecodeSuccess(DateTime.parse(value)),
    _ => DecodeFailure('Expected an ISO 8601 date, got: $json'),
  };

  @override
  JsonValue encode(DateTime value) => JsonString(value.toIso8601String());
}
```

Create `packages/typed_graphql_codegen/test/goldens/schema_types/support/packages/scalar_codecs/pubspec.yaml.txt`:

```text
name: scalar_codecs
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  typed_graphql: ^0.0.1
```

Create `packages/typed_graphql_codegen/test/support/generated_package.dart`:

```dart
import 'dart:io';

import 'package:test/test.dart';

import 'golden_case.dart';

/// A temporary Dart package that holds a golden case's generated code, so
/// that the analyzer and the VM check it.
final class GeneratedPackage(
  /// The package's directory.
  final Directory directory,

  /// The case whose goldens and support files it holds.
  final GoldenCase golden,

  /// The workspace root, where `typed_graphql` and `typed_graphql_client` are.
  final String workspace,
) {
  /// Describes the package; [write] creates its files.
  this;

  /// Writes the pubspec, the lints, the goldens and the support files.
  void write() {
    final files = <String, String>{
      'pubspec.yaml':
          '''
name: generated_${golden.name}
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
${_dependencies()}dev_dependencies:
  lints: ^6.1.0
dependency_overrides:
  typed_graphql:
    path: $workspace/packages/typed_graphql
  typed_graphql_client:
    path: $workspace/packages/typed_graphql_client
''',
      'analysis_options.yaml':
          File(
            '$workspace/analysis_options.yaml',
          ).readAsStringSync().replaceFirst(
            'language:\n',
            'language:\n    strict-casts: true\n',
          ),
      ...golden.goldens,
      ...golden.support,
    };
    for (final entry in files.entries) {
      final file = File('${directory.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
  }

  // The path dependencies, sorted: the two workspace packages and the local
  // packages of the case's `support/packages/`.
  String _dependencies() {
    final paths = <String, String>{
      'typed_graphql': '$workspace/packages/typed_graphql',
      'typed_graphql_client': '$workspace/packages/typed_graphql_client',
      for (final path in golden.support.keys)
        if (path.startsWith('packages/'))
          path.split('/')[1]: 'packages/${path.split('/')[1]}',
    };
    return [
      for (final name in paths.keys.toList()..sort())
        '  $name:\n    path: ${paths[name]}\n',
    ].join();
  }

  /// Runs `dart [arguments]` in [directory] and expects exit code 0.
  static void run(Directory directory, List<String> arguments) {
    final result = Process.runSync(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: directory.path,
    );
    expect(
      result.exitCode,
      0,
      reason:
          'dart ${arguments.join(' ')}:\n${result.stdout}\n${result.stderr}',
    );
  }
}
```

Create `packages/typed_graphql_codegen/test/support/golden_case.dart`:

```dart
import 'dart:io';

import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

/// One directory of `test/goldens/`: the input project, the generated files
/// it must produce and the extra files its analysis needs.
final class GoldenCase {
  /// The case in the directory [directory].
  GoldenCase(this.directory);

  /// Every case, sorted by name.
  static List<GoldenCase> all() => [
    for (final entity in Directory('test/goldens').listSync())
      if (entity is Directory) GoldenCase(entity),
  ]..sort((a, b) => a.name.compareTo(b.name));

  /// The case's directory.
  final Directory directory;

  /// The directory's name.
  String get name => directory.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

  /// The configuration read from `input/typed_graphql.yaml`.
  CodegenConfig get config {
    final result = CodegenConfig.parse(
      File('${directory.path}/input/typed_graphql.yaml').readAsStringSync(),
      path: 'typed_graphql.yaml',
    );
    if (result is! ConfigSuccess) throw StateError('$name: $result');
    return result.config;
  }

  /// The input files by path relative to `input/`.
  Map<String, String> get inputs => _read('input', (path) => true);

  /// The schema file, at the path the configuration names.
  ProjectFile get schema {
    final location = config.schema;
    if (location is! SchemaFile) throw StateError('$name: needs a schema file');
    return ProjectFile(location.path, inputs[location.path] ?? '');
  }

  /// Every `.graphql` input but the schema.
  List<ProjectFile> get documents => [
    for (final entry in inputs.entries)
      if (entry.key.endsWith('.graphql') && entry.key != schema.path)
        ProjectFile(entry.key, entry.value),
  ];

  /// The generated files the case expects, by their path (the `.golden`
  /// suffix removed).
  Map<String, String> get goldens => _read(
    'output',
    (path) => path.endsWith('.golden'),
  ).map((path, text) => MapEntry(path.substring(0, path.length - 7), text));

  /// The extra files of the analysis package, by path (the `.txt` suffix
  /// removed).
  Map<String, String> get support => _read(
    'support',
    (path) => path.endsWith('.txt'),
  ).map((path, text) => MapEntry(path.substring(0, path.length - 4), text));

  /// Writes [files] as the case's goldens, replacing the old ones.
  void writeGoldens(List<GeneratedFile> files) {
    final output = Directory('${directory.path}/output');
    if (output.existsSync()) output.deleteSync(recursive: true);
    for (final file in files) {
      final target = File('${output.path}/${file.path}.golden');
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(file.text);
    }
  }

  Map<String, String> _read(String folder, bool Function(String) isWanted) {
    final root = Directory('${directory.path}/$folder');
    if (!root.existsSync()) return {};
    final files = <String, String>{};
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path
          .substring(root.path.length + 1)
          .replaceAll(r'\', '/');
      if (isWanted(path)) files[path] = entity.readAsStringSync();
    }
    return files;
  }
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/input_object_emitter_test.dart test/generated_code_test.dart test/generator/client_generator_generate_test.dart test/generator/generated_names_test.dart test/generator/schema_type_usage_test.dart test/golden_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Update the package files**

Create `packages/typed_graphql_codegen/dart_test.yaml`:

```yaml
tags:
  analysis:
    # Generated code is analyzed in a temporary package; pub get and the
    # analyzer start processes.
    timeout: 5x
```

- [ ] **Step 4: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/emit/input_field.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -35,7 +35,7 @@ final class const InputField({
     final DartType type = mapper.of(input.type, imports);
     return InputField(
       graphQLName: input.name,
-      dartName: _name(input.name),
+      dartName: dartNameOf(input.name),
       value: type,
       isOptional: input.type is! NonNullType || input.defaultValue != null,
       doc: _doc(input),
@@ -50,7 +50,7 @@ final class const InputField({
     Imports imports,
   ) => InputField(
     graphQLName: input.name,
-    dartName: _name(input.name),
+    dartName: dartNameOf(input.name),
     value: mapper.ofNonNull(input.type, imports),
     isOptional: false,
     doc: _doc(input),
@@ -76,7 +76,8 @@ final class const InputField({
 
   static final RegExp _list = RegExp(r'(^|[^\w$.])List<');
 
-  static String _name(String name) => const DartNames().memberName(
+  /// The Dart member name of the input field named [name].
+  static String dartNameOf(String name) => const DartNames().memberName(
     name,
     reservedMembers: DartNames.objectMembers,
   );
```

In `packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -161,12 +161,14 @@ final class OneOfInputEmitter {
   }
 
   void _writeEquality(String variant, String name, DartWriter writer) {
-    final String other = _names.freeName('other', <String>[name]);
+    // The parameter keeps the name `other` (avoid_renaming_method_parameters);
+    // a field of that name is read through `this`.
+    final String own = name == 'other' ? 'this.other' : name;
     writer
       ..line('@override')
       ..arrow(
-        'bool operator ==(Object $other)',
-        '$other is $variant && $other.$name == $name',
+        'bool operator ==(Object other)',
+        'other is $variant && other.$name == $own',
       )
       ..line()
       ..line('@override')
```

In `packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,5 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
-import 'dart_names.dart';
 import 'dart_string_literal.dart';
 import 'dart_writer.dart';
 import 'imports.dart';
@@ -170,19 +169,20 @@ final class RegularInputEmitter {
   }
 
   void _writeEquality(String name, List<InputField> fields, DartWriter writer) {
-    final String other = const DartNames().freeName('other', <String>[
-      for (final InputField field in fields) field.dartName,
-    ]);
+    // The parameter keeps the name `other` (avoid_renaming_method_parameters);
+    // a field of that name is read through `this`.
+    String own(InputField field) =>
+        field.dartName == 'other' ? 'this.other' : field.dartName;
     writer
       ..line('@override')
-      ..arrowJoined('bool operator ==(Object $other)', <String>[
-        '$other is $name',
+      ..arrowJoined('bool operator ==(Object other)', <String>[
+        'other is $name',
         for (final InputField field in fields)
           if (field.holdsList)
-            'const client.DataEquality().equals($other.${field.dartName}, '
-                '${field.dartName})'
+            'const client.DataEquality().equals(other.${field.dartName}, '
+                '${own(field)})'
           else
-            '$other.${field.dartName} == ${field.dartName}',
+            'other.${field.dartName} == ${own(field)}',
       ], '&&')
       ..line()
       ..line('@override');
```

Create `packages/typed_graphql_codegen/lib/src/emit/schema_types_emitter.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'dart_writer.dart';
import 'enum_emitter.dart';
import 'generated_header.dart';
import 'imports.dart';
import 'input_object_emitter.dart';
import 'type_mapper.dart';

/// Writes the schema-types library: the enums and input objects the
/// documents use (spec §7).
///
/// {@category codegen}
final class SchemaTypesEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const SchemaTypesEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  /// The text of the library for [types], generated from the file [source].
  ///
  /// [types] are written in the order given; with none, the library holds
  /// only its header and imports nothing.
  String emit(List<SchemaType> types, {required String source}) {
    final imports = Imports();
    final body = DartWriter();
    for (final (int index, SchemaType type) in types.indexed) {
      if (index > 0) body.line();
      switch (type) {
        case EnumType():
          const EnumEmitter().emit(type, body);
        case InputObjectType():
          InputObjectEmitter(mapper).emit(type, body, imports);
        case _:
          throw ArgumentError.value(type, 'types', 'is not an enum or input');
      }
    }
    if (types.isNotEmpty) {
      imports.package(
        'package:typed_graphql_client/typed_graphql_client.dart',
        prefix: 'client',
      );
    }
    if (types.any((type) => type is InputObjectType)) {
      imports.package(
        'package:typed_graphql/typed_graphql.dart',
        prefix: 'graphql',
      );
    }
    final head = DartWriter();
    const GeneratedHeader().write(head, source: source);
    imports.write(head);
    head.line();
    return types.isEmpty ? head.text : '${head.text}\n${body.text}';
  }
}
```

In `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,11 +1,18 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../config/codegen_config.dart';
+import '../emit/schema_types_emitter.dart';
+import '../emit/type_mapper.dart';
 import '../project/project_file.dart';
+import 'client_project.dart';
 import 'client_project_loader.dart';
 import 'client_project_result.dart';
+import 'generated_file.dart';
+import 'generated_names.dart';
+import 'generation_result.dart';
 import 'rules/named_operations_rule.dart';
 import 'rules/unsupported_directives_rule.dart';
+import 'schema_type_usage.dart';
 
 /// Generates typed Dart client code from a schema and `.graphql` documents.
 ///
@@ -56,13 +63,22 @@ final class const ClientGenerator(final CodegenConfig config) {
   /// Checks the schema and the documents as `generate` will read them;
   /// returns every diagnostic, warnings included, in report order.
   ///
+  /// This is `generate(...).diagnostics`: it includes the name checks.
+  List<Diagnostic> check({
+    required ProjectFile schema,
+    required List<ProjectFile> documents,
+  }) => generate(schema: schema, documents: documents).diagnostics;
+
+  /// Generates the files of the project.
+  ///
   /// When the schema cannot be loaded, the documents are only parsed: their
   /// syntax errors come after the schema's, and no validation error is
-  /// reported.
+  /// reported. With any error the result has no files.
   ///
   /// [schema] is the schema file and [documents] the files the configuration's
-  /// `documents` globs matched; nothing is written.
-  List<Diagnostic> check({
+  /// `documents` globs matched; nothing is written. For now the only file is
+  /// the schema-types library at [CodegenConfig.schemaTypes].
+  GenerationResult generate({
     required ProjectFile schema,
     required List<ProjectFile> documents,
   }) {
@@ -71,8 +87,41 @@ final class const ClientGenerator(final CodegenConfig config) {
       rules,
     ).load(schema: schema, documents: documents);
     return switch (result) {
-      ClientProjectLoaded(:final warnings) => warnings,
-      ClientProjectFailed(:final diagnostics) => diagnostics,
+      ClientProjectFailed(:final diagnostics) => GenerationResult(
+        const [],
+        diagnostics,
+      ),
+      ClientProjectLoaded(:final project, :final warnings) => _generate(
+        project,
+        schema.path,
+        warnings,
+      ),
     };
   }
+
+  GenerationResult _generate(
+    ClientProject project,
+    String schemaPath,
+    List<Diagnostic> warnings,
+  ) {
+    final types = SchemaTypeUsage(
+      project.schema.schema,
+    ).of(project.document.document);
+    final names = GeneratedNames(
+      mappedCoreTypes: [
+        for (final mapping in config.scalars.values)
+          if (mapping.type.library == null) mapping.type.name,
+      ],
+    );
+    types.forEach(names.registerSchemaType);
+    if (names.diagnostics.isNotEmpty) {
+      return GenerationResult(const [], [...warnings, ...names.diagnostics]);
+    }
+    final text = SchemaTypesEmitter(
+      TypeMapper(project.schema.schema, config.scalars),
+    ).emit(types, source: schemaPath);
+    return GenerationResult([
+      GeneratedFile(config.schemaTypes, text),
+    ], warnings);
+  }
 }
```

Create `packages/typed_graphql_codegen/lib/src/generator/generated_file.dart`:

```dart
/// A file the generator writes.
///
/// {@category codegen}
final class const GeneratedFile(
  /// The path relative to the configuration file, with `/` separators.
  final String path,

  /// The content of the file.
  final String text,
) {
  /// Creates a file.
  this;

  @override
  bool operator ==(Object other) =>
      other is GeneratedFile && other.path == path && other.text == text;

  @override
  int get hashCode => Object.hash(path, text);

  @override
  String toString() => 'GeneratedFile($path)';
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';
import '../emit/input_field.dart';

/// The top-level names one generation declares, with what declared each, so
/// that two declarations with one name, or a name that hides a Dart type the
/// generated code uses, are diagnostics instead of broken code.
final class GeneratedNames {
  /// Creates a registry; [mappedCoreTypes] are the `dart:core` types the
  /// configuration maps scalars to, which are as reserved as
  /// [reservedTypeNames].
  GeneratedNames({Iterable<String> mappedCoreTypes = const []})
    : _reserved = {...reservedTypeNames, ...mappedCoreTypes};

  /// The Dart types the generated code uses by their bare names.
  static const Set<String> reservedTypeNames = {
    'bool',
    'double',
    'int',
    'num',
    'String',
    'List',
    'Map',
    'Object',
    'Null',
    'Never',
    'Function',
    'Record',
    'Type',
    'Symbol',
    'Deprecated',
    'override',
    'DateTime',
    'Duration',
    'Uri',
    'BigInt',
  };

  final Set<String> _reserved;
  final Map<String, (String, SourceSpan?)> _declared = {};
  final List<Diagnostic> _diagnostics = [];

  /// The problems found so far, in registration order.
  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Records that [declarer] (such as `the enum 'Role'`) declares [name].
  void register(String name, String declarer, SourceSpan? span) {
    if (_reserved.contains(name)) {
      _diagnostics.add(
        Diagnostic(
          .reservedTypeName,
          .error,
          "The generated name '$name' would hide the Dart type '$name' the "
          'generated code uses.',
          span: span,
        ),
      );
    }
    final first = _declared[name];
    if (first == null) {
      _declared[name] = (declarer, span);
      return;
    }
    _diagnostics.add(
      Diagnostic(
        .generatedNameCollision,
        .error,
        "The generated name '$name' is declared twice: by ${first.$1} and by "
        '$declarer.',
        span: span,
        related: [?first.$2],
      ),
    );
  }

  /// Records every name the classes of the enum or input object [type]
  /// declare; any other type declares none.
  void registerSchemaType(SchemaType type) {
    const names = DartNames();
    final base = names.typeName(type.name);
    switch (type) {
      case EnumType():
        final declarer = "the enum '${type.name}'";
        for (final name in [base, '${base}Known', '${base}Unknown']) {
          register(name, declarer, type.span);
        }
      case InputObjectType(:final fields, :final isOneOf):
        final declarer = "the input object '${type.name}'";
        register(base, declarer, type.span);
        if (isOneOf) {
          for (final field in fields) {
            final variant = names.capitalized(
              InputField.dartNameOf(field.name),
            );
            register('$base$variant', declarer, type.span);
          }
        }
      case _:
    }
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/generation_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'generated_file.dart';

/// What `ClientGenerator.generate` produced: the files and every diagnostic,
/// warnings included.
///
/// {@category codegen}
final class GenerationResult(
  List<GeneratedFile> files,
  List<Diagnostic> diagnostics,
) {
  /// Creates a result; a result with errors has no [files].
  this;

  /// The files to write, sorted by path; empty when there are errors.
  final List<GeneratedFile> files = List.unmodifiable(files);

  /// Every diagnostic, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);

  /// Whether a diagnostic is an error.
  bool get hasErrors => diagnostics.any((diagnostic) => diagnostic.isError);
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/schema_type_usage.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Finds the schema types the documents use, which are the only ones
/// generated (spec §7, "pruned").
///
/// Starts from the named type of every variable and of every selected field,
/// keeps the enums and input objects, and follows the fields of each input
/// object with a work list: input types may be cyclic.
final class const SchemaTypeUsage(final Schema schema) {
  /// Creates the finder for [schema].
  this;

  /// The enums and input objects [document] uses, sorted by name.
  List<SchemaType> of(Document document) {
    final collector = _NamedTypes(schema);
    const AstWalker().walk(document, collector);
    final used = <String, SchemaType>{};
    final pending = [...collector.types];
    while (pending.isNotEmpty) {
      final type = pending.removeLast();
      if (used.containsKey(type.name)) continue;
      switch (type) {
        case EnumType():
          used[type.name] = type;
        case InputObjectType(:final fields):
          used[type.name] = type;
          pending.addAll(_typesOf(fields));
        case _:
      }
    }
    return [
      for (final entry
          in used.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        entry.value,
    ];
  }

  Iterable<SchemaType> _typesOf(List<InputValue> fields) => [
    for (final field in fields) ?schema.namedTypeOf(field.type),
  ];
}

/// Collects the named types of variables and fields in one walk.
final class _NamedTypes extends AstVisitor {
  _NamedTypes(this._schema) : _info = TypeInfo(_schema);

  final Schema _schema;
  final TypeInfo _info;
  final List<SchemaType> types = [];

  @override
  VisitAction enter(Node node) {
    _info.enter(node);
    final TypeRef? type = switch (node) {
      VariableDefinition(:final type) => type,
      Field() => _info.type,
      _ => null,
    };
    if (type == null) return VisitAction.next;
    if (_schema.namedTypeOf(type) case final named?) types.add(named);
    return VisitAction.next;
  }

  @override
  void leave(Node node) => _info.leave(node);
}
```

In `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,6 +11,8 @@ export 'src/config/dart_reference.dart';
 export 'src/config/scalar_mapping.dart';
 export 'src/config/schema_location.dart';
 export 'src/generator/client_generator.dart';
+export 'src/generator/generated_file.dart';
+export 'src/generator/generation_result.dart';
 export 'src/project/project_file.dart';
 export 'src/schema/schema_load_result.dart';
 export 'src/schema/schema_loader.dart';
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/input_object_emitter_test.dart test/generated_code_test.dart test/generator/client_generator_generate_test.dart test/generator/generated_names_test.dart test/generator/schema_type_usage_test.dart test/golden_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- `ClientGenerator.generate` returns a `GenerationResult` (`GeneratedFile`s and
  diagnostics) and writes the schema-types library at `schema_types`: the
  enums and input objects the documents use, with `@oneOf` inputs as sealed
  classes; `check` is `generate(...).diagnostics`.
- `GQL507` (a Dart name declared twice) and `GQL508` (a generated name that
  hides a Dart type the generated code uses) are reported before any file is
  written.
- Golden cases in `test/goldens/` and an analysis test that analyzes and runs
  the generated code in a temporary package (tag `analysis`).
```

In `packages/typed_graphql_codegen/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,20 +4,20 @@
 ![Role](https://img.shields.io/badge/role-codegen-blue)
 ![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)
 
-**Check a GraphQL project for Dart client code generation: read `typed_graphql.yaml`, load the schema and validate the `.graphql` operations, with every problem reported at its file, line and column.** No code is generated yet. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
+**Check a GraphQL project for Dart client code generation: read `typed_graphql.yaml`, load the schema and validate the `.graphql` operations, with every problem reported at its file, line and column.** So far it generates the library of the enums and input objects the operations use; operation classes are not generated yet. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
 > **Status: under construction.** This release reads the project's
 > configuration, `typed_graphql.yaml` (`CodegenConfig`), and checks a project:
 > `ClientGenerator.check` loads the schema, parses and validates the
 > `.graphql` documents as one fragment graph, and reports every problem with
-> its file, line and column. It does not generate code yet; client generation
-> arrives in M10 and the SDL-first server generator in M8 (see the
+> its file, line and column. `ClientGenerator.generate` also writes the
+> schema-types library; operation classes and the CLI arrive in M10 and the SDL-first server generator in M8 (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
 It does not depend on `analyzer`. The
 [Client Code Generation guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/doc/client_codegen.md)
 lists the configuration keys, shows a check and lists the codes `GQL500` to
-`GQL506`.
+`GQL508`.
 
 ## License
 
```

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -124,6 +124,8 @@ and are never reused.
 | `GQL504` | error | A document uses `@defer` or `@stream`, which the generator does not support yet. |
 | `GQL505` | error | The configuration maps a scalar that the schema does not declare as a custom scalar: it is unknown, is not a scalar, or is built in. |
 | `GQL506` | warning | No document matches `documents`. |
+| `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`). |
+| `GQL508` | error | A name the generator would declare hides a Dart type the generated code uses, such as `List`, or a `dart:core` type a scalar is mapped to. |
 
 The problems of the schema and of the documents keep the codes of the core:
 the schema's `GQL1xx` and the operation rules' `GQL2xx`.
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
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/README.md packages/typed_graphql_codegen/dart_test.yaml packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/lib/src/emit/input_field.dart packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart packages/typed_graphql_codegen/lib/src/emit/schema_types_emitter.dart packages/typed_graphql_codegen/lib/src/generator/client_generator.dart packages/typed_graphql_codegen/lib/src/generator/generated_file.dart packages/typed_graphql_codegen/lib/src/generator/generated_names.dart packages/typed_graphql_codegen/lib/src/generator/generation_result.dart packages/typed_graphql_codegen/lib/src/generator/schema_type_usage.dart packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart packages/typed_graphql_codegen/test/generated_code_test.dart packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart packages/typed_graphql_codegen/test/generator/generated_names_test.dart packages/typed_graphql_codegen/test/generator/schema_type_usage_test.dart packages/typed_graphql_codegen/test/golden_test.dart packages/typed_graphql_codegen/test/goldens/no_documents/input/schema.graphql packages/typed_graphql_codegen/test/goldens/no_documents/input/typed_graphql.yaml packages/typed_graphql_codegen/test/goldens/no_documents/output/lib/schema.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/schema_types/input/lib/user.graphql packages/typed_graphql_codegen/test/goldens/schema_types/input/schema.graphql packages/typed_graphql_codegen/test/goldens/schema_types/input/typed_graphql.yaml packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/schema.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/schema_types/support/bin/round_trip.dart.txt packages/typed_graphql_codegen/test/goldens/schema_types/support/packages/scalar_codecs/lib/scalar_codecs.dart.txt packages/typed_graphql_codegen/test/goldens/schema_types/support/packages/scalar_codecs/pubspec.yaml.txt packages/typed_graphql_codegen/test/support/generated_package.dart packages/typed_graphql_codegen/test/support/golden_case.dart
git commit -q -m "feat(typed_graphql_codegen): generate the schema-types library" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Document the schema types

The guide gains a Generating program and a Schema types section (enums, input objects, `@oneOf`, scalars, pruning, the file header); the README and the CHANGELOG say what works now.

Commit on the branch: `6f168a5`.

**Files:**
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/README.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`

**Interfaces:**
- Consumes: Tasks 1-7.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- The guide documents generation and the generated schema types (enums, input
  objects, `@oneOf`, scalars, pruning, the file header) and lists `GQL507` and
  `GQL508`.
```

In `packages/typed_graphql_codegen/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,7 +16,7 @@
 
 It does not depend on `analyzer`. The
 [Client Code Generation guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/doc/client_codegen.md)
-lists the configuration keys, shows a check and lists the codes `GQL500` to
+lists the configuration keys, shows a check and a generation, describes the generated enums, input objects and scalars, and lists the codes `GQL500` to
 `GQL508`.
 
 ## License
```

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -1,12 +1,14 @@
 # Client Code Generation
 
 `typed_graphql_codegen` turns a GraphQL schema and the `.graphql` operations
-of a Dart project into typed client code. This version checks a project: it
-reads the configuration file, loads the schema, parses and validates every
-document as one fragment graph, and reports each problem as a diagnostic at
-`file:line:column`. It does not write code yet; generation arrives with the
-next part of the stage. Bad input never throws: a problem is a diagnostic
-with a stable code, in a sealed result or a list.
+of a Dart project into typed client code. This version checks a project and
+generates the library of the schema's types: the enums and input objects the
+documents use, with the scalars mapped to Dart types. It reads the
+configuration file, loads the schema, parses and validates every document as
+one fragment graph, and reports each problem as a diagnostic at
+`file:line:column`; classes for operations and fragments arrive next. Bad
+input never throws: a problem is a diagnostic with a stable code, in a sealed
+result or a list.
 
 ## Configuration
 
@@ -110,6 +112,254 @@ queries/name.graphql:1:25: error GQL205: Cannot query field "nam" on type "User"
 
 A project with no error is ready to generate; a warning does not stop it.
 
+## Generating
+
+`ClientGenerator(config).generate` takes the same files as `check` and
+returns a `GenerationResult`: the diagnostics of `check`, and the files to
+write, each a `GeneratedFile` with a path and a text. A result with an error
+has no files. The engine writes nothing itself; the caller (the command line
+or a `build_runner` builder) puts the files on disk.
+
+```dart
+import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';
+
+void main() {
+  final result = CodegenConfig.parse(
+    'schema: schema.graphql\n',
+    path: 'typed_graphql.yaml',
+  );
+  if (result is! ConfigSuccess) {
+    throw StateError('the configuration is valid');
+  }
+  final generation = ClientGenerator(result.config).generate(
+    schema: const ProjectFile('schema.graphql', '''
+type Query {
+  role: Role
+}
+
+enum Role {
+  ADMIN
+  GUEST @deprecated(reason: "Use ADMIN.")
+}
+'''),
+    documents: const [ProjectFile('role.graphql', 'query GetRole { role }')],
+  );
+  for (final file in generation.files) {
+    print('// ${file.path}');
+    print(file.text);
+  }
+}
+```
+
+It prints:
+
+```text
+// lib/schema.graphql.dart
+// GENERATED CODE - DO NOT MODIFY BY HAND.
+// Generated by typed_graphql_codegen from schema.graphql.
+// dart format off
+
+import 'package:typed_graphql_client/typed_graphql_client.dart' as client;
+
+/// The enum `Role`.
+sealed class Role implements client.DataEnum {
+  /// The value named [raw]: a [RoleKnown], or a [RoleUnknown] for a name
+  /// this code does not know.
+  factory Role.parse(String raw) {
+    for (final value in RoleKnown.values) {
+      if (value.raw == raw) return value;
+    }
+    return RoleUnknown(raw);
+  }
+
+  /// Reads and writes the values of `Role`.
+  static const client.DataCodec<Role> codec = client.EnumDataCodec(Role.parse);
+}
+
+/// The values of [Role] this code knows.
+enum RoleKnown implements Role {
+  /// `ADMIN`.
+  admin('ADMIN'),
+
+  /// `GUEST`.
+  @Deprecated('Use ADMIN.')
+  guest('GUEST');
+
+  const RoleKnown(this.raw);
+
+  @override
+  final String raw;
+}
+
+/// A value of [Role] this code does not know, such as one added to the
+/// schema after the code was generated.
+final class RoleUnknown implements Role {
+  /// Creates the value named [raw].
+  const RoleUnknown(this.raw);
+
+  @override
+  final String raw;
+
+  @override
+  bool operator ==(Object other) => other is RoleUnknown && other.raw == raw;
+
+  @override
+  int get hashCode => raw.hashCode;
+
+  @override
+  String toString() => 'RoleUnknown($raw)';
+}
+```
+
+## Schema types
+
+The file at `schema_types` holds what the documents reach: the enums and
+input objects they use, directly or through other input objects. The examples
+below are excerpts of the golden files in the package's
+`test/goldens/schema_types`, which the tests regenerate, analyze and run.
+
+Every generated file starts with a header. `// dart format off` is part of
+it: the text is not formatted by hand, and a project that runs
+`dart format` must not rewrite generated files, or the next generation would
+differ from what is on disk.
+
+```text
+// GENERATED CODE - DO NOT MODIFY BY HAND.
+// Generated by typed_graphql_codegen from schema.graphql.
+// dart format off
+```
+
+### Enums
+
+An enum is a `sealed class` with a parser, an `enum` of the values the code
+knows (`XKnown`, with the Dart name in lower camel case and the GraphQL name
+as `raw`) and a class for any other name (`XUnknown`). A server may add a
+value after the code was generated; the client then reads it as `XUnknown`
+instead of failing, and a `switch` over the sealed class must handle it. A
+deprecated value is `@Deprecated`, and descriptions become doc comments.
+
+```text
+sealed class Role implements client.DataEnum {
+  factory Role.parse(String raw) {
+    for (final value in RoleKnown.values) {
+      if (value.raw == raw) return value;
+    }
+    return RoleUnknown(raw);
+  }
+}
+
+enum RoleKnown implements Role {
+  admin('ADMIN'),
+  editor('EDITOR'),
+  @Deprecated('Use EDITOR.')
+  viewer('VIEWER');
+}
+```
+
+```text
+String label(Role role) => switch (role) {
+  RoleKnown.admin => 'Administrator',
+  RoleKnown.editor || RoleKnown.viewer => 'Other',
+  RoleUnknown(:final raw) => 'Unknown role $raw',
+};
+```
+
+### Input objects
+
+An input object is a `final class` with a `const` constructor, a `codec`, a
+`toJson`, value equality and `toString`. The shape of a field follows its
+type and default:
+
+| Field | Dart | Constructor |
+|---|---|---|
+| `ids: [ID!]!` (non-null, no default) | `List<String>` | `required` |
+| `role: Role` (nullable) | `Optional<Role?>` | absent unless given |
+| `name: String = "x"` (nullable, with a default) | `Optional<String?>` | absent unless given; the doc comment shows the default |
+| `limit: Int! = 10` (non-null, with a default) | `Optional<int>` | absent unless given |
+
+A field that is not given is `Optional.absent()`, which is not the same as
+`null`: `toJson` writes only the present values, so the server applies its
+default to an absent field and sees an explicit `null` otherwise. A name that
+Dart reserves (`default`) gets a `$` suffix (`default$`); the JSON key stays
+`default`.
+
+```text
+final class UserFilter implements client.DataObject {
+  const UserFilter({
+    required this.ids,
+    this.role = const graphql.Optional.absent(),
+    this.name = const graphql.Optional.absent(),
+  });
+
+  final graphql.Optional<Role?> role;
+  final List<String> ids;
+
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    if (role case graphql.Present(:final value))
+      'role': _roleCodec.write(value),
+    'ids': _idsCodec.write(ids),
+  });
+}
+```
+
+### `@oneOf` input objects
+
+An input object with `@oneOf` is a `sealed class` with one `final class`
+variant per field, `SearchByName` for the field `name`; the type system then
+allows exactly one field, as the specification does. Reading a value with
+none or several fields is a `DataFormatException`.
+
+```text
+sealed class SearchBy implements client.DataObject { ... }
+
+final class SearchByName implements SearchBy {
+  const SearchByName(this.name);
+  final String name;
+}
+
+final class SearchById implements SearchBy {
+  const SearchById(this.id);
+  final String id;
+}
+```
+
+### Scalars
+
+The built-in scalars have a fixed mapping:
+
+| Scalar | Dart type | Codec |
+|---|---|---|
+| `Int` | `int` | `IntCodec` |
+| `Float` | `double` | `FloatCodec` |
+| `String` | `String` | `StringCodec` |
+| `Boolean` | `bool` | `BooleanCodec` |
+| `ID` | `String` | `IdCodec` |
+
+A custom scalar listed under `scalars:` in `typed_graphql.yaml` uses its
+`type` and its `codec`; the generated file imports the codec's library with a
+prefix. A custom scalar without a mapping is a `JsonValue`: the generator
+guesses nothing, and the value stays as the server sent it.
+
+```text
+scalars:
+  DateTime:
+    type: DateTime
+    codec: package:scalar_codecs/scalar_codecs.dart#DateTimeCodec
+```
+
+```text
+final graphql.Optional<DateTime?> since;
+final graphql.Optional<graphql.JsonValue?> after;
+```
+
+### Pruning
+
+Only what the documents reach is generated. In the golden schema, the enum
+`Unused` and the input object `Unreached` are not used by any operation, so
+they have no class; `Role`, `UserFilter` (and `UserFilter`'s own field types),
+`SearchBy` and `Paging` are. A project with no document gets an empty
+library, and a schema is free to be large.
+
 ## Diagnostics
 
 The codes of the code generator are the range `GQL5xx`. Ids are public API
````

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
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/README.md packages/typed_graphql_codegen/doc/client_codegen.md
git commit -q -m "docs(typed_graphql_codegen): document the schema types" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Address the M10b review

Fixes the four important findings of the M10b review (`.superpowers/m10-reports/m10b-review.md`) and the minors the ruling kept: list fields of `@oneOf` variants compare by value (`DataEquality`); enum values and input fields that map to one Dart member are `GQL507`; `client` and `graphql` are reserved members so they cannot shadow the import prefixes; the analysis test skips itself when compiled (`Platform.resolvedExecutable` is not `dart`); `DartWriter` fixes (an argument-less call, per-comment fence state, whitespace-only doc lines); and the missing tests (a list in a `@oneOf`, `[[Int]]`, a field named `client`, an enum from an introspection schema).

Commit on the branch: `c18f16b`.

**Files:**
- Modify: `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`, `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart`, `packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart`, `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart`, `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`
- Test: `packages/typed_graphql_codegen/test/emit/dart_names_test.dart`, `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart`, `packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart`, `packages/typed_graphql_codegen/test/generated_code_test.dart`, `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`, `packages/typed_graphql_codegen/test/generator/generated_names_test.dart`, `packages/typed_graphql_codegen/test/goldens/schema_types/input/schema.graphql`, `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/schema.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/schema_types/support/bin/round_trip.dart.txt`, `packages/typed_graphql_codegen/test/support/golden_case.dart`

**Interfaces:**
- Consumes: Tasks 3-7.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/emit/dart_names_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -45,6 +45,16 @@ void main() {
     );
   });
 
+  test('memberName escapes the import prefixes of the generated code', () {
+    expect(
+      [
+        for (final name in ['client', 'graphql'])
+          names.memberName(name, reservedMembers: DartNames.objectMembers),
+      ],
+      [r'client$', r'graphql$'],
+    );
+  });
+
   test('memberName leaves a member the caller did not reserve', () {
     expect(names.memberName('toJson'), 'toJson');
   });
```

In `packages/typed_graphql_codegen/test/emit/dart_writer_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -109,4 +109,28 @@ void main() {
     writer.arrowJoined('bool get x', <String>['a', 'b'], '&&');
     expect(writer.text, 'bool get x => a && b;\n');
   });
+
+  test('arrow keeps a call without arguments whole when it is too long', () {
+    final DartWriter writer = DartWriter();
+    final String codec = '${'A' * 80}()';
+    writer.arrow('int get x', 'f($codec)');
+    expect(writer.text, 'int get x => f(\n  $codec,\n);\n');
+  });
+
+  test('doc forgets an unclosed fence of the previous comment', () {
+    final DartWriter writer = DartWriter();
+    writer
+      ..doc('```\ncode')
+      ..doc('```\nmore\n```');
+    expect(
+      writer.text,
+      '/// ```text\n/// code\n/// ```text\n/// more\n/// ```\n',
+    );
+  });
+
+  test('doc leaves no trailing whitespace and drops carriage returns', () {
+    final DartWriter writer = DartWriter();
+    writer.doc('a  \r\n   \nb');
+    expect(writer.text, '/// a\n///\n/// b\n');
+  });
 }
````

In `packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -400,4 +400,41 @@ final class Doc implements client.DataObject {
 ''',
     );
   });
+
+  test('a oneOf variant that holds a list compares its items', () {
+    final text = emit(
+      'input Pick @oneOf { ids: [ID!], name: String }',
+      'Pick',
+    );
+    expect(
+      text,
+      allOf(
+        contains(
+          'other is PickIds &&\n'
+          '      const client.DataEquality().equals(other.ids, ids);',
+        ),
+        contains('int get hashCode => const client.DataEquality().hash(ids);'),
+        contains('other is PickName && other.name == name'),
+      ),
+    );
+  });
+
+  test('a field named like an import prefix gets a dollar', () {
+    final text = emit(
+      'input Prefixed { client: [Int!], graphql: Int }',
+      'Prefixed',
+    );
+    expect(
+      text,
+      allOf(
+        contains(r'final graphql.Optional<List<int>?> client$;'),
+        contains(r'final graphql.Optional<int?> graphql$;'),
+        contains(
+          r'const client.DataEquality().equals(other.client$, client$)',
+        ),
+        isNot(contains(' client;')),
+        isNot(contains(' graphql;')),
+      ),
+    );
+  });
 }
```

In `packages/typed_graphql_codegen/test/generated_code_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,9 +11,17 @@ import 'support/generated_package.dart';
 import 'support/golden_case.dart';
 
 void main() {
+  // Under `dart test --compiler exe` the running executable is the compiled
+  // test, not the SDK's `dart`, so the commands below cannot run; the JIT
+  // job runs this suite.
+  final String tool = Platform.resolvedExecutable.split(RegExp(r'[/\\]')).last;
+  final String? skip = tool == 'dart' || tool == 'dart.exe'
+      ? null
+      : 'the test is compiled: run it with the dart tool (JIT)';
   final workspace = Directory.current.parent.parent.path;
   for (final golden in GoldenCase.all()) {
     group(golden.name, () {
+      // Assigned by setUp, which runs before every test of the group.
       late Directory package;
 
       setUp(() {
@@ -23,13 +31,17 @@ void main() {
 
       tearDown(() => package.deleteSync(recursive: true));
 
-      test('passes the analyzer and round trips its sample values', () {
-        GeneratedPackage.run(package, ['pub', 'get', '--offline']);
-        GeneratedPackage.run(package, ['analyze', '--fatal-infos']);
-        if (golden.support.containsKey('bin/round_trip.dart')) {
-          GeneratedPackage.run(package, ['run', 'bin/round_trip.dart']);
-        }
-      });
+      test(
+        'passes the analyzer and round trips its sample values',
+        skip: skip,
+        () {
+          GeneratedPackage.run(package, ['pub', 'get', '--offline']);
+          GeneratedPackage.run(package, ['analyze', '--fatal-infos']);
+          if (golden.support.containsKey('bin/round_trip.dart')) {
+            GeneratedPackage.run(package, ['run', 'bin/round_trip.dart']);
+          }
+        },
+      );
     });
   }
 }
```

In `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import 'package:test/test.dart';
+import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';
 
 const _schema = ProjectFile('schema.graphql', '''
@@ -154,4 +155,30 @@ type Query {
     expect(result.diagnostics.single.code.id, 'GQL506');
     expect(result.files, hasLength(1));
   });
+
+  test('an introspection enum reached through __type is generated', () {
+    final built = const SchemaBuilder().fromSdl(
+      const Parser().parse(Source(_schema.text)).requireDocument(),
+    ) as BuildSuccess;
+    final result = ClientGenerator(configOf('schema: schema.json\n')).generate(
+      schema: ProjectFile(
+        'schema.json',
+        built.schema.toIntrospection().toString(),
+      ),
+      documents: const [
+        ProjectFile(
+          'lib/a.graphql',
+          'query A { __type(name: "Role") { kind } }\n',
+        ),
+      ],
+    );
+    expect(result.hasErrors, isFalse, reason: '${result.diagnostics}');
+    expect(
+      result.files.single.text,
+      allOf(
+        contains(r'sealed class $$TypeKind'),
+        contains(r'enum $$TypeKindKnown'),
+      ),
+    );
+  });
 }
```

In `packages/typed_graphql_codegen/test/generator/generated_names_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -94,5 +94,47 @@ type Query { a: Int }
         ],
       );
     });
+
+    test('enum values with one Dart name are a GQL507', () {
+      expect(
+        problems(
+          'enum Status { NOT_FOUND notFound OK }\ntype Query { a: Int }',
+        ),
+        [
+          "The generated member name 'notFound' of the enum 'Status' is "
+              "declared twice: by the value 'NOT_FOUND' and by the value "
+              "'notFound'.",
+        ],
+      );
+    });
+
+    test('input fields with one Dart name are a GQL507 at the field', () {
+      final schema = (const SchemaBuilder().fromSdl(
+        const Parser()
+            .parse(
+              Source(
+                'input In { first_name: Int firstName: Int }\n'
+                'type Query { a: Int }',
+              ),
+            )
+            .requireDocument(),
+        source: Source(
+          'input In { first_name: Int firstName: Int }\n'
+          'type Query { a: Int }',
+        ),
+      ) as BuildSuccess).schema;
+      final names = GeneratedNames()
+        ..registerSchemaType(schema.typeNamed('In')!);
+      final diagnostic = names.diagnostics.single;
+      expect(diagnostic.code, DiagnosticCode.generatedNameCollision);
+      expect(
+        diagnostic.message,
+        "The generated member name 'firstName' of the input object 'In' is "
+        "declared twice: by the field 'first_name' and by the field "
+        "'firstName'.",
+      );
+      expect(diagnostic.span, isNotNull);
+      expect(diagnostic.related, hasLength(1));
+    });
   });
 }
```

In `packages/typed_graphql_codegen/test/goldens/schema_types/input/schema.graphql`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -19,11 +19,13 @@ input UserFilter {
   ids: [ID!]!
   nested: UserFilter
   since: DateTime
+  matrix: [[Int]]
 }
 
 input SearchBy @oneOf {
   name: String
   id: ID
+  ids: [ID!]
 }
 
 "Names that Dart reserves or that the generated class already has."
@@ -31,6 +33,7 @@ input Paging {
   default: Int
   other: String!
   after: Cursor
+  client: Int
 }
 
 input Unreached {
```

In `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/schema.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -13,6 +13,7 @@ final class Paging implements client.DataObject {
     required this.other,
     this.default$ = const graphql.Optional.absent(),
     this.after = const graphql.Optional.absent(),
+    this.client$ = const graphql.Optional.absent(),
   });
 
   factory Paging._read(graphql.JsonObject json, client.DataContext context) =>
@@ -20,6 +21,7 @@ final class Paging implements client.DataObject {
         default$: _default$Codec.optionalField(json, 'default', context),
         other: _otherCodec.field(json, 'other', context),
         after: _afterCodec.optionalField(json, 'after', context),
+        client$: _client$Codec.optionalField(json, 'client', context),
       );
 
   /// Reads and writes the values of `Paging`.
@@ -35,6 +37,9 @@ final class Paging implements client.DataObject {
   static const client.DataCodec<graphql.JsonValue?> _afterCodec =
       client.NullableDataCodec(client.JsonDataCodec());
 
+  static const client.DataCodec<int?> _client$Codec =
+      client.NullableDataCodec(client.ScalarDataCodec(graphql.IntCodec()));
+
   /// The field `default`.
   final graphql.Optional<int?> default$;
 
@@ -44,6 +49,9 @@ final class Paging implements client.DataObject {
   /// The field `after`.
   final graphql.Optional<graphql.JsonValue?> after;
 
+  /// The field `client`.
+  final graphql.Optional<int?> client$;
+
   @override
   graphql.JsonObject toJson() => graphql.JsonObject({
     if (default$ case graphql.Present(:final value))
@@ -51,6 +59,8 @@ final class Paging implements client.DataObject {
     'other': _otherCodec.write(other),
     if (after case graphql.Present(:final value))
       'after': _afterCodec.write(value),
+    if (client$ case graphql.Present(:final value))
+      'client': _client$Codec.write(value),
   });
 
   @override
@@ -58,18 +68,21 @@ final class Paging implements client.DataObject {
       other is Paging &&
       other.default$ == default$ &&
       other.other == this.other &&
-      other.after == after;
+      other.after == after &&
+      other.client$ == client$;
 
   @override
   int get hashCode => Object.hashAll([
     default$.hashCode,
     other.hashCode,
     after.hashCode,
+    client$.hashCode,
   ]);
 
   @override
   String toString() =>
-      'Paging(default\$: ${default$}, other: $other, after: $after)';
+      'Paging(default\$: ${default$}, other: $other, after: $after, '
+      'client\$: ${client$})';
 }
 
 /// A user role.
@@ -130,8 +143,9 @@ sealed class SearchBy implements client.DataObject {
       switch (json.fields.keys.toList()) {
         ['name'] => SearchByName(_nameCodec.field(json, 'name', context)),
         ['id'] => SearchById(_idCodec.field(json, 'id', context)),
+        ['ids'] => SearchByIds(_idsCodec.field(json, 'ids', context)),
         _ => throw const client.DataFormatException(
-          'Expected exactly one of the fields name, id.',
+          'Expected exactly one of the fields name, id, ids.',
         ),
       };
 
@@ -144,6 +158,9 @@ sealed class SearchBy implements client.DataObject {
 
   static const client.DataCodec<String> _idCodec =
       client.ScalarDataCodec(graphql.IdCodec());
+
+  static const client.DataCodec<List<String>> _idsCodec =
+      client.ListDataCodec(client.ScalarDataCodec(graphql.IdCodec()));
 }
 
 /// [SearchBy] with its field `name`.
@@ -192,6 +209,31 @@ final class SearchById implements SearchBy {
   String toString() => 'SearchById($id)';
 }
 
+/// [SearchBy] with its field `ids`.
+final class SearchByIds implements SearchBy {
+  /// Creates the input object with its field `ids`.
+  const SearchByIds(this.ids);
+
+  /// The field `ids`.
+  final List<String> ids;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    'ids': SearchBy._idsCodec.write(ids),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is SearchByIds &&
+      const client.DataEquality().equals(other.ids, ids);
+
+  @override
+  int get hashCode => const client.DataEquality().hash(ids);
+
+  @override
+  String toString() => 'SearchByIds($ids)';
+}
+
 /// The input object `UserFilter`.
 final class UserFilter implements client.DataObject {
   /// Creates the input object.
@@ -201,6 +243,7 @@ final class UserFilter implements client.DataObject {
     this.name = const graphql.Optional.absent(),
     this.nested = const graphql.Optional.absent(),
     this.since = const graphql.Optional.absent(),
+    this.matrix = const graphql.Optional.absent(),
   });
 
   factory UserFilter._read(
@@ -212,6 +255,7 @@ final class UserFilter implements client.DataObject {
     ids: _idsCodec.field(json, 'ids', context),
     nested: _nestedCodec.optionalField(json, 'nested', context),
     since: _sinceCodec.optionalField(json, 'since', context),
+    matrix: _matrixCodec.optionalField(json, 'matrix', context),
   );
 
   /// Reads and writes the values of `UserFilter`.
@@ -235,6 +279,19 @@ final class UserFilter implements client.DataObject {
         client.ScalarDataCodec(scalar_0.DateTimeCodec()),
       );
 
+  static const client.DataCodec<List<List<int?>?>?> _matrixCodec =
+      client.NullableDataCodec(
+        client.ListDataCodec(
+          client.NullableDataCodec(
+            client.ListDataCodec(
+              client.NullableDataCodec(
+                client.ScalarDataCodec(graphql.IntCodec()),
+              ),
+            ),
+          ),
+        ),
+      );
+
   /// The field `role`.
   final graphql.Optional<Role?> role;
 
@@ -250,6 +307,9 @@ final class UserFilter implements client.DataObject {
   /// The field `since`.
   final graphql.Optional<DateTime?> since;
 
+  /// The field `matrix`.
+  final graphql.Optional<List<List<int?>?>?> matrix;
+
   @override
   graphql.JsonObject toJson() => graphql.JsonObject({
     if (role case graphql.Present(:final value))
@@ -261,6 +321,8 @@ final class UserFilter implements client.DataObject {
       'nested': _nestedCodec.write(value),
     if (since case graphql.Present(:final value))
       'since': _sinceCodec.write(value),
+    if (matrix case graphql.Present(:final value))
+      'matrix': _matrixCodec.write(value),
   });
 
   @override
@@ -270,7 +332,8 @@ final class UserFilter implements client.DataObject {
       other.name == name &&
       const client.DataEquality().equals(other.ids, ids) &&
       other.nested == nested &&
-      other.since == since;
+      other.since == since &&
+      const client.DataEquality().equals(other.matrix, matrix);
 
   @override
   int get hashCode => Object.hashAll([
@@ -279,10 +342,11 @@ final class UserFilter implements client.DataObject {
     const client.DataEquality().hash(ids),
     nested.hashCode,
     since.hashCode,
+    const client.DataEquality().hash(matrix),
   ]);
 
   @override
   String toString() =>
       'UserFilter(role: $role, name: $name, ids: $ids, nested: $nested, '
-      'since: $since)';
+      'since: $since, matrix: $matrix)';
 }
```

In `packages/typed_graphql_codegen/test/goldens/schema_types/support/bin/round_trip.dart.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,16 +12,22 @@ void main() {
     role: const Optional.present(RoleKnown.admin),
     name: const Optional.present(null),
     since: Optional.present(DateTime.utc(2026, 10, 15)),
+    matrix: const Optional.present([
+      [1, null],
+      [2],
+    ]),
   );
   const paging = Paging(
     other: 'x',
     default$: Optional.present(3),
     after: Optional.present(JsonString('c1')),
+    client$: Optional.present(4),
   );
   _check('UserFilter', UserFilter.codec, filter);
   _check('Paging', Paging.codec, paging);
   _check('SearchBy', SearchBy.codec, const SearchByName('Ada'));
   _check('SearchBy', SearchBy.codec, const SearchById('7'));
+  _check('SearchBy', SearchBy.codec, const SearchByIds(['1', '2']));
   _check('Role', Role.codec, RoleKnown.editor);
   _check('Role', Role.codec, const RoleUnknown('NEW'));
   if (!paging.toString().contains(r'default$: ')) {
```

In `packages/typed_graphql_codegen/test/support/golden_case.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -42,9 +42,9 @@ final class GoldenCase {
 
   /// Every `.graphql` input but the schema.
   List<ProjectFile> get documents => [
-    for (final entry in inputs.entries)
-      if (entry.key.endsWith('.graphql') && entry.key != schema.path)
-        ProjectFile(entry.key, entry.value),
+    for (final path in inputs.keys.toList()..sort())
+      if (path.endsWith('.graphql') && path != schema.path)
+        ProjectFile(path, inputs[path]!),
   ];
 
   /// The generated files the case expects, by their path (the `.golden`
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/dart_names_test.dart test/emit/dart_writer_test.dart test/emit/input_object_emitter_test.dart test/generated_code_test.dart test/generator/client_generator_generate_test.dart test/generator/generated_names_test.dart)
```

Expected: FAIL. The new and changed tests fail on the behaviour this task fixes (assertion failures; a test that uses a name the next step adds does not compile).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -18,6 +18,9 @@ final class DartNames {
     'codec',
     'decode',
     'fragments',
+    // Prefixes of the imports the instance members use.
+    'client',
+    'graphql',
   };
 
   /// Members every generated enum has, including those of `Enum`.
```

In `packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -45,8 +45,10 @@ final class DartWriter {
   ///
   /// A bare Markdown fence that opens a block gets the language `text`.
   void doc(String text) {
+    // A comment is a unit: an unclosed fence must not leak into the next one.
+    _isInFence = false;
     for (final String content in text.split('\n')) {
-      line(_docLine(content));
+      line(_docLine(content.trimRight()));
     }
   }
 
@@ -158,7 +160,11 @@ final class DartWriter {
   // calls until each line fits.
   void _breakCall(String text) {
     final int open = text.indexOf('(');
-    if (fits('$text,') || open < 0 || !text.endsWith(')')) {
+    // A call without arguments cannot be broken: `(` and `)` stay together.
+    if (fits('$text,') ||
+        open < 0 ||
+        !text.endsWith(')') ||
+        open + 1 == text.length - 1) {
       line('$text,');
       return;
     }
```

In `packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -152,7 +152,7 @@ final class OneOfInputEmitter {
           })
           ..line('});')
           ..line();
-        _writeEquality(variant, name, writer);
+        _writeEquality(variant, field, writer);
         writer
           ..line()
           ..line('@override')
@@ -160,18 +160,25 @@ final class OneOfInputEmitter {
       });
   }
 
-  void _writeEquality(String variant, String name, DartWriter writer) {
+  void _writeEquality(String variant, InputField field, DartWriter writer) {
+    final String name = field.dartName;
     // The parameter keeps the name `other` (avoid_renaming_method_parameters);
     // a field of that name is read through `this`.
     final String own = name == 'other' ? 'this.other' : name;
+    final String same = field.holdsList
+        ? 'const client.DataEquality().equals(other.$name, $own)'
+        : 'other.$name == $own';
+    final String hash = field.holdsList
+        ? 'const client.DataEquality().hash($name)'
+        : '$name.hashCode';
     writer
       ..line('@override')
-      ..arrow(
-        'bool operator ==(Object other)',
-        'other is $variant && other.$name == $own',
-      )
+      ..arrowJoined('bool operator ==(Object other)', [
+        'other is $variant',
+        same,
+      ], '&&')
       ..line()
       ..line('@override')
-      ..line('int get hashCode => $name.hashCode;');
+      ..arrow('int get hashCode', hash);
   }
 }
```

In `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -77,26 +77,77 @@ final class GeneratedNames {
   /// Records every name the classes of the enum or input object [type]
   /// declare; any other type declares none.
   void registerSchemaType(SchemaType type) {
-    const names = DartNames();
-    final base = names.typeName(type.name);
     switch (type) {
       case EnumType():
-        final declarer = "the enum '${type.name}'";
-        for (final name in [base, '${base}Known', '${base}Unknown']) {
-          register(name, declarer, type.span);
-        }
-      case InputObjectType(:final fields, :final isOneOf):
-        final declarer = "the input object '${type.name}'";
-        register(base, declarer, type.span);
-        if (isOneOf) {
-          for (final field in fields) {
-            final variant = names.capitalized(
-              InputField.dartNameOf(field.name),
-            );
-            register('$base$variant', declarer, type.span);
-          }
-        }
+        _registerEnum(type);
+      case InputObjectType():
+        _registerInputObject(type);
       case _:
     }
   }
+
+  void _registerEnum(EnumType type) {
+    const names = DartNames();
+    final base = names.typeName(type.name);
+    final declarer = "the enum '${type.name}'";
+    for (final name in [base, '${base}Known', '${base}Unknown']) {
+      register(name, declarer, type.span);
+    }
+    _registerMembers(declarer, [
+      for (final value in type.values)
+        (
+          names.memberName(value.name, reservedMembers: DartNames.enumMembers),
+          "the value '${value.name}'",
+          value.span ?? type.span,
+        ),
+    ]);
+  }
+
+  void _registerInputObject(InputObjectType type) {
+    const names = DartNames();
+    final base = names.typeName(type.name);
+    final declarer = "the input object '${type.name}'";
+    register(base, declarer, type.span);
+    if (type.isOneOf) {
+      for (final field in type.fields) {
+        final variant = names.capitalized(InputField.dartNameOf(field.name));
+        register('$base$variant', declarer, type.span);
+      }
+      return;
+    }
+    _registerMembers(declarer, [
+      for (final field in type.fields)
+        (
+          InputField.dartNameOf(field.name),
+          "the field '${field.name}'",
+          field.span ?? type.span,
+        ),
+    ]);
+  }
+
+  // Several GraphQL names can give one Dart member name (`RED` and `red`,
+  // `first_name` and `firstName`), which would not compile.
+  void _registerMembers(
+    String owner,
+    List<(String, String, SourceSpan?)> members,
+  ) {
+    final Map<String, (String, SourceSpan?)> seen = {};
+    for (final (name, declarer, span) in members) {
+      final first = seen[name];
+      if (first == null) {
+        seen[name] = (declarer, span);
+        continue;
+      }
+      _diagnostics.add(
+        Diagnostic(
+          .generatedNameCollision,
+          .error,
+          "The generated member name '$name' of $owner is declared twice: "
+          'by ${first.$1} and by $declarer.',
+          span: span,
+          related: [?first.$2],
+        ),
+      );
+    }
+  }
 }
```

In `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,7 +2,8 @@
 /// operations and SDL-first server code, without the analyzer.
 ///
 /// Under construction: so far the package reads `typed_graphql.yaml`
-/// ([CodegenConfig]); see the package README.
+/// ([CodegenConfig]) and [ClientGenerator] writes the Dart enums and input
+/// objects of the schema; see the package README.
 library;
 
 export 'src/config/codegen_config.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/dart_names_test.dart test/emit/dart_writer_test.dart test/emit/input_object_emitter_test.dart test/generated_code_test.dart test/generator/client_generator_generate_test.dart test/generator/generated_names_test.dart)
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
git add packages/typed_graphql_codegen/lib/src/emit/dart_names.dart packages/typed_graphql_codegen/lib/src/emit/dart_writer.dart packages/typed_graphql_codegen/lib/src/emit/one_of_input_emitter.dart packages/typed_graphql_codegen/lib/src/generator/generated_names.dart packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart packages/typed_graphql_codegen/test/emit/dart_names_test.dart packages/typed_graphql_codegen/test/emit/dart_writer_test.dart packages/typed_graphql_codegen/test/emit/input_object_emitter_test.dart packages/typed_graphql_codegen/test/generated_code_test.dart packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart packages/typed_graphql_codegen/test/generator/generated_names_test.dart packages/typed_graphql_codegen/test/goldens/schema_types/input/schema.graphql packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/schema.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/schema_types/support/bin/round_trip.dart.txt packages/typed_graphql_codegen/test/support/golden_case.dart
git commit -q -m "fix(typed_graphql_codegen): address the M10b review" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

With the choice this plan makes (`.superpowers/m10-open-questions.md`):

- Question 1: `Optional` lives in the core's `protocol/` (Task 1); M5 should use the same type, and the merge keeps one.
- Question 3: enums are `sealed class Role implements DataEnum`, `enum RoleKnown implements Role`, `final class RoleUnknown`; `parse` loops over `RoleKnown.values` (a `switch` naming a deprecated value trips `deprecated_member_use_from_same_package`).
- Question 5: every nullable input field and variable is `Optional<T?>`.
- Question 11: the contract lives in `typed_graphql_client` from M10 on; the package says it holds only that contract until M11.

## Self-review

- Spec coverage: section 2 (Tasks 1, 2), section 7 "Layout", "Enums", "Input objects", "Scalars" (Tasks 3-7), section 8 (Task 2), section 9 `GQL507`/`GQL508` (Tasks 6, 7, 9), section 11 (Task 7), section 13 (Tasks 2, 8).
- Every code block in this plan is the content of a commit that passed the green check; no placeholder remains.
- Type consistency: each task's Produces block is extracted from its commit, and later tasks consume those names.

## After the plan

M10c (`2026-10-15-m10c-operations-and-fragments.md`) follows on the same branch.
