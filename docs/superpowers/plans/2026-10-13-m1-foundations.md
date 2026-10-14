# M1 Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the old `graphql_dart` package with the `typed_graphql` pub workspace: seven package skeletons, the code rules and their ratchet, CI, the core's diagnostics model and protocol data types, and the process documents.

**Architecture:** The workspace root `pubspec.yaml` lists seven members under `packages/`. The code rules run once, at the workspace root, in `test/quality/`. They are a text scanner and do not use `analyzer`. The core (`packages/typed_graphql`) gets two of its five layer folders:
- `diagnostics/`: `Source`, spans, the `DiagnosticCode` catalog, `Diagnostic`, `DiagnosticSink`.
- `protocol/`: `JsonValue`, `JsonReader`, `DecodeResult`, `GraphQLError`, `GraphQLRequest`, `ResponsePayload`.

A test in the core enforces the order of the layers.

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, null-aware elements), pub workspaces, `package:test`, `package:lints`, `package:meta`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-13-typed-graphql-design.md` (architecture), `docs/requirements.md`, `docs/roadmap.md` (the M1 row). Stage M1 has no stage spec of its own; this plan argues from those three files.

## Global Constraints

- `sdk: ^3.13.0` in every package (R0.5). Workspace members use `resolution: workspace`. Use stable Dart 3.13 features only, with no experiment flags.
- The core package is pure Dart: no `dart:io` and no dependency except `meta`. It must compile with dart2js and dart2wasm (R0.6).
- M1 declares no dependencies other than the workspace packages, `meta`, `test` and `lints`.
- `analysis_options.yaml` is typed_openapi's, verbatim (R10.1). Never silence a lint: no `// ignore:` anywhere.
- Code limits (`CLAUDE.md`, enforced from Task 4 on):
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters;
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or one sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no top-level functions other than `main`, no `utils`/`helpers` names.
- Bad input never throws; it gives a `DecodeFailure` or a `Diagnostic`. Exceptions are only for programmer errors.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action.
- Commits use Conventional Commits, one per task, with the message given in the task. Executors append the trailers their session instructs.
- Everything in the repository is in English.
- Run every command from the repository root unless a step says otherwise. Use `(cd packages/<name> && …)` so the shell stays at the root.

## Review Focus

The five failure modes most likely to bite a user, given what the spec implies. Each one has a test that pins it, in the task named.

1. **Line terminators and offsets in `Source`.** Take a document with `\r\n`, a lone `\r`, U+2028, a byte order mark, a surrogate pair, and an offset at its very end. It must get graphql-js's lines and columns. An offset past the end must be a `RangeError`, never a wrong location. Pinned in Task 6:
   - `places the line feed on the line it ends`;
   - `accepts the end of the document`;
   - `does not treat U+2028 and U+2029 as line terminators`;
   - `counts columns in UTF-16 code units`;
   - `rejects an offset outside the document`.
2. **Untrusted JSON.** Each of these inputs must give a `DecodeFailure` or a defined value, and never a throw or a stack overflow, on the VM or on dart2js: `1e400`, integers past 2^53, 100 000 nested arrays, repeated keys, and a Dart list that contains itself. Pinned in Task 9:
   - `rejects a number too large to be finite`;
   - `reads integers past 2^53 - 1 without a safe int`;
   - `rejects nesting past maxDepth before decoding`;
   - `keeps the last value of a repeated key`;
   - `rejects a list that contains itself`.
3. **`GraphQLError` as real servers write it.** Real output can have `1.0` as a path index (JavaScript numbers), `null` for absent fields, an empty `locations`, and extra keys such as `code`. These must be read as graphql-js reads them, and a bad shape must fail with a JSONPath. Pinned in Task 10:
   - `reads 1.0 as the index 1, since the web cannot tell them apart`;
   - `treats null and absent fields alike`;
   - `reads empty locations as none`;
   - `ignores keys the spec does not define`;
   - `rejects an index that is negative or not whole`.
4. **A `DiagnosticSink` fed many warnings and errors.** Warnings never count toward `maxErrors`. Exactly one `GQL000` appears, at the first dropped error, and the order is kept. Pinned in Task 7:
   - `does not count warnings toward the limit`;
   - `replaces the first error over the limit with GQL000 and stops`.
5. **The ratchet on Windows paths and on code it could misread.** Comments, strings, interpolations, raw strings, record types, primary constructors and map patterns must neither hide a violation nor invent one. Pinned in:
   - Task 2: `blanks interpolations, with the strings inside them`, `does not read a map pattern as a block`;
   - Task 3: `a field is not callable, even with a closure or a record type`, `skips the parameters of a primary constructor and enum values`;
   - Task 4: `paths with Windows separators are read`, `dynamic is rejected in code but not in comments or strings`;
   - Task 5: `reads Windows paths`.

## M1 design decisions

These were made while writing this plan; the spec leaves them open.

1. **Layer order is total:** `diagnostics < language < protocol < schema < validation`. A library may import its own layer and lower ones. `protocol` needs `SourceLocation`, and `schema` will need `DecodeResult` for `ScalarCodec` in M3. M1 creates only `diagnostics/` and `protocol/`.
2. **Where `Source` lives.** `Source`, `SourceLocation` and `SourceSpan` live in `diagnostics/`, the lowest layer, because `Diagnostic` needs spans.
3. **Lines and columns.** Columns count UTF-16 code units. `\r\n`, `\n` and `\r` end a line; U+2028 and U+2029 do not. An offset outside `0..length` is a `RangeError`. The line table is built on the first `locationOf` call (R1.7, Source part).
4. **`DiagnosticCode` is one enum** with stable ids, and `values` serves the catalog tests. M1 seeds only `GQL000 diagnosticLimitReached`. The enum's doc comment holds the range table (R1.12). The file is permanently exempt from the size limit because it is a catalog with no logic.
5. **`DiagnosticSink`:**
   - keeps report order;
   - `maxErrors` is 100 (graphql-js) and counts errors only;
   - at the first dropped error it adds one `GQL000`, then ignores every report.
6. **`JsonValue` is a sealed family of final classes.**
   - There is one `JsonNumber` type, because the web cannot tell `1` from `1.0`. `asInt` reads whole numbers up to 2^53 - 1.
   - NaN and the infinities are rejected.
7. **`JsonReader` pre-scans nesting** (`maxDepth` 512 by default) before `jsonDecode`, so deep input cannot overflow the dart2js stack. A repeated key keeps its last value, as `jsonDecode` does.
8. **`DecodeResult`** (`DecodeSuccess` | `DecodeFailure` with a `PathSegment` path) lives in `protocol/`. M3's `ScalarCodec` will reuse it. A failure prints its path as JSONPath (`$.errors[0].message`).
9. **The response type is `sealed ResponsePayload`**, which is `ExecutionResult` | `RequestErrorResult`. The name `GraphQLResponse` stays free for the client (M11).
10. **`GraphQLRequest` fields are all optional** (APQ sends no `query`), and unknown keys are ignored (GraphQL over HTTP).
11. **The code-rules ratchet runs once, at the workspace root,** over `packages/*/{lib,bin,test,tool}` and the root `test/`. It is text-based, needs no `analyzer`, and exempts constructors from the parameter limit. Its allowlists start empty.
12. **Every package has a VM-only `test/pubspec_test.dart`** (R0.5), because `dart test` exits with code 79 when a package has no tests.
13. **The core's `JsonFieldReader` is internal** (`lib/src/protocol/`, not exported). It is the one place that reads object fields for the three `decode` methods.
14. **Package READMEs follow basalt's skeleton.** Links use absolute GitHub URLs so they also work on pub.dev.

## Spec deviations and findings

Bring these to the user with the plan.

1. **`JsonValue` is not an extension type.** Spec principle 2 calls it one. An extension type cannot be sealed or matched with `is`, so the plan uses a sealed class family. The decisions log already rejects extension types for data; the spec text should be amended.
2. **The layer arrow is ambiguous.** Spec §1's arrow `protocol ← diagnostics, language` is read here as "protocol depends on diagnostics and language" (decision 1). The user needs to confirm this; if the reading is wrong, `LayerRule.layers` changes.
3. **`Source` is not in `language/`.** Spec §2 lists `Source` under the language layer, but the plan puts it in `diagnostics/` (decision 2).
4. **The verbatim `analysis_options.yaml` shows its typed_openapi origin.** Its comments mention typed_openapi's documents and a 3.10 floor. It also leaves out the lints added in Dart 3.12/3.13 (`simple_directive_paths`, `no_dynamic_casts`, `no_raw_types`). R10.1 says verbatim, so the plan copies it unchanged. Adapting it is a decision for the user.
5. **Name clashes for M9 and M10.** `SourceSpan` and `SourceLocation` clash with `package:source_span`, and `Diagnostic` clashes with `analyzer`. The builder and codegen must import with prefixes.
6. **CRLF columns.** An offset at the `\n` of a `\r\n` stays on the `\r`'s line, at the next column. graphql-js gives column 0 there, which is not a valid 1-based column.
7. **`jsonDecode('1e400')` gives `Infinity` on the VM.** `JsonReader` rejects it ("is not a finite number").
8. **R10.5 is only partly met.** It asks for dart2js and dart2wasm runs for the client too. In M1 the client has no code and only a VM-only test, so the web job covers the core and gets a comment saying the client joins in M11.
9. **Dart 3.13 lint traps found while verifying.** `CLAUDE.md` records each of them:
   - an undocumented primary constructor needs a documented `this;` body (`public_member_api_docs`);
   - `@immutable` may be used only where every constructor is `const`;
   - a `late` field initializer cannot read a non-declaring parameter;
   - a generic `==` must test `is C<Object?>`;
   - a `when` guard does not count toward exhaustiveness.
10. **What could not be verified locally:**
    - the CI matrix on exactly 3.13.0 (3.13.1 was used);
    - macOS and Windows;
    - `actionlint`.

    The workflow was parsed as YAML, and its loops were run on Linux.

## File map

| Path | Responsibility | Task |
|---|---|---|
| `pubspec.yaml`, `analysis_options.yaml`, `LICENSE` | Workspace root, lints, license | 1 |
| `packages/<seven>/{pubspec.yaml,LICENSE,CHANGELOG.md,README.md,lib/<name>.dart,test/pubspec_test.dart}` | Package skeletons | 1 |
| `test/quality/blanked_code.dart` | Dart text with comments and string contents blanked; bracket depths | 2 |
| `test/quality/nesting_meter.dart` | Depth of control blocks per line | 2 |
| `test/quality/declaration.dart`, `signature.dart`, `declaration_scanner.dart` | Types, members and functions of a file, with their line ranges and parameter counts | 3 |
| `test/quality/code_rules.dart`, `workspace_files.dart`, `code_rules_test.dart` | The rules, the file walk, the ratchet with empty allowlists | 4 |
| `packages/typed_graphql/test/quality/layer_rule.dart`, `layers_test.dart` | Layer order and pure-Dart imports of the core | 5 |
| `packages/typed_graphql/lib/src/diagnostics/source*.dart` | `Source`, `SourceLocation`, `SourceSpan` | 6 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic*.dart` | `DiagnosticSeverity`, `DiagnosticCode`, `Diagnostic`, `DiagnosticSink` | 7 |
| `packages/typed_graphql/lib/src/protocol/{path_segment,decode_result,json_value}.dart` | Decoding results and the JSON model | 8 |
| `packages/typed_graphql/lib/src/protocol/json_reader.dart` | Text and plain Dart objects to `JsonValue` | 9 |
| `packages/typed_graphql/lib/src/protocol/{json_field_reader,graphql_error}.dart` | Field access for decoders; the error format | 10 |
| `packages/typed_graphql/lib/src/protocol/{graphql_request,response_payload}.dart` | Request and response formats | 11 |
| `.github/workflows/ci.yml` | CI (R10.5) | 12 |
| `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, `docs/superpowers/HANDOFF.md`, `docs/README.md`, core `README.md` | Process and user documents (R11.4) | 13 |

## The green check

Every task ends with this check. "Green" means each command exits 0.

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages test   # Task 1: `packages` only (no test/ yet)
dart analyze --fatal-infos
dart test                                                       # from Task 2 on (root test/ exists)
for p in packages/*/; do (cd "$p" && dart test) || exit 1; done
```

---
### Task 1: Workspace and package skeletons

**Files:**
- Delete: `lib/` (all of it), `example/`, `test/graphql_dart_test.dart`, `pubspec.yaml`, `analysis_options.yaml`, `README.md`, `CHANGELOG.md`
- Create: `pubspec.yaml`, `analysis_options.yaml`, `LICENSE`
- Create, for each of `typed_graphql`, `typed_graphql_server`, `typed_graphql_shelf`, `typed_graphql_client`, `typed_graphql_codegen`, `typed_graphql_builder` and `typed_graphql_conformance`, these files under `packages/<name>/`: `pubspec.yaml`, `LICENSE`, `CHANGELOG.md`, `README.md`, `lib/<name>.dart`
- Test: `packages/<name>/test/pubspec_test.dart` (the same file in all seven packages)
- Keep: `.gitignore`, `tool/fetch_reference.sh`, `docs/`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - the workspace: the root `pubspec.yaml` named `typed_graphql_workspace`, with dev dependencies `lints` and `test`;
  - seven members with `resolution: workspace`;
  - `typed_graphql` depends on `meta: ^1.15.0`;
  - every package has a library `lib/<name>.dart` that exports nothing yet;
  - the root `analysis_options.yaml` applies to every package.

- [ ] **Step 1: Delete the old package**

```bash
git rm -r -q lib example test pubspec.yaml analysis_options.yaml README.md CHANGELOG.md
```

Run: `git status --short | grep -v '^D ' || true`
Expected: no output. Every change is a deletion, and `docs/`, `tool/` and `.gitignore` are untouched.

- [ ] **Step 2: Write the failing test (core package)**

Create `packages/typed_graphql/test/pubspec_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('requires Dart 3.13 (R0.5)', () {
    expect(pubspec, contains('sdk: ^3.13.0'));
  });

  test('resolves in the workspace', () {
    expect(pubspec, contains('resolution: workspace'));
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `(cd packages/typed_graphql && dart test)`
Expected: FAIL with `No pubspec.yaml file found - run this command in your project folder.`

- [ ] **Step 4: Create the workspace root**

Create `pubspec.yaml`:

```yaml
name: typed_graphql_workspace
description: The typed_graphql pub workspace and its code-rules suite. Never published.
publish_to: none

environment:
  sdk: ^3.13.0

dev_dependencies:
  lints: ^6.1.0
  test: ^1.31.0

workspace:
  - packages/typed_graphql
  - packages/typed_graphql_server
  - packages/typed_graphql_shelf
  - packages/typed_graphql_client
  - packages/typed_graphql_codegen
  - packages/typed_graphql_builder
  - packages/typed_graphql_conformance
```

Create `analysis_options.yaml`. This is `typed_openapi/analysis_options.yaml`, verbatim (R10.1). Do not edit its comments or rules, even where they mention typed_openapi or Dart 3.10; finding 4 of this plan explains why.

```yaml
# Lints for the whole workspace. Rules come from Effective Dart
# (https://dart.dev/effective-dart) and the lint catalog
# (https://dart.dev/tools/linter-rules/all); the reasoning, the counts and the
# rules left out are in docs/code-quality-review.md (section 7).
#
# Rules since Dart 3.11 or newer are not listed: the minimum SDK is 3.10.
# Every rule here passes with zero findings today, so `dart analyze packages`
# must print "No issues found!".
include: package:lints/recommended.yaml

linter:
  rules:
    # Types and signatures (Effective Dart: Design, Usage)
    - always_declare_return_types
    - type_annotate_public_apis
    - avoid_annotating_with_dynamic
    - avoid_types_on_closure_parameters
    - avoid_types_as_parameter_names
    - avoid_dynamic_calls
    - always_put_required_named_parameters_first
    - avoid_final_parameters
    - parameter_assignments
    - avoid_unused_constructor_parameters
    - matching_super_parameters
    - tighten_type_of_initializing_formals

    # Immutability and class design (Effective Dart: Design)
    - prefer_final_locals
    - prefer_final_in_for_each
    - prefer_const_constructors
    - prefer_const_declarations
    - prefer_const_constructors_in_immutables
    - prefer_const_literals_to_create_immutables
    - avoid_field_initializers_in_const_classes
    - avoid_returning_this
    - avoid_setters_without_getters
    - use_setters_to_change_properties
    - use_to_and_as_if_applicable
    - avoid_implementing_value_types
    - prefer_mixin
    - avoid_classes_with_only_static_members
    - use_enums
    - sort_constructors_first
    - sort_unnamed_constructors_first
    - prefer_asserts_in_initializer_lists
    - prefer_asserts_with_message
    - test_types_in_equals

    # Control flow and expressions (Effective Dart: Usage)
    - avoid_bool_literals_in_conditional_expressions
    - literal_only_boolean_expressions
    - no_literal_bool_comparisons
    - no_self_assignments
    - avoid_multiple_declarations_per_line
    - prefer_if_elements_to_conditional_expressions
    - prefer_null_aware_method_calls
    - unnecessary_statements
    - unnecessary_breaks
    - unnecessary_lambdas
    - join_return_with_assignment
    - switch_on_type
    - use_is_even_rather_than_modulo
    - use_truncating_division
    - prefer_int_literals
    - noop_primitive_operations
    - use_named_constants
    - use_string_buffers
    - unnecessary_null_aware_operator_on_extension_on_nullable

    # Errors, async and resources (Effective Dart: Usage; the generator never prints)
    - avoid_catching_errors
    - avoid_catches_without_on_clauses
    - only_throw_errors
    - throw_in_finally
    - avoid_void_async
    - avoid_slow_async_io
    - cancel_subscriptions
    - close_sinks
    - avoid_print

    # Web compatibility (the runtime is compiled to JS and Wasm)
    - avoid_double_and_int_checks
    - avoid_js_rounded_ints
    - no_runtimetype_tostring
    - avoid_type_to_string

    # Strings, imports and files (Effective Dart: Style)
    - prefer_single_quotes
    - unnecessary_raw_strings
    - use_raw_strings
    - leading_newlines_in_multiline_strings
    - directives_ordering
    - combinators_ordering
    - file_names
    - library_names
    - eol_at_end_of_file
    - prefer_relative_imports
    - conditional_uri_does_not_exist
    - unnecessary_library_directive
    - unreachable_from_main
    - require_trailing_commas

    # Documentation, deprecation, tests and pubspec
    - public_member_api_docs
    - missing_code_block_language_in_doc_comment
    - deprecated_consistency
    - deprecated_member_use_from_same_package
    - unnecessary_ignore
    - use_test_throws_matchers
    - sort_pub_dependencies

    # Staged, not enabled yet: each has a few findings in files M9 is going to
    # change. Enable one at a time after M9 merges and its findings are fixed
    # (docs/code-quality-plan.md, phase 3):
    #   strict-casts, strict-inference, strict-raw-types (analyzer: language:)
    #   avoid_positional_boolean_parameters, avoid_redundant_argument_values,
    #   avoid_equals_and_hash_code_on_mutable_classes (add @immutable),
    #   cast_nullable_to_non_nullable, comment_references, discarded_futures,
    #   unawaited_futures, async_return_with_no_await,
    #   missing_whitespace_between_adjacent_strings, avoid_escaping_inner_quotes,
    #   prefer_expression_function_bodies, prefer_foreach,
    #   prefer_constructors_over_static_methods, unnecessary_null_checks,
    #   unnecessary_parenthesis, prefer_void_to_null, omit_obvious_local_variable_types,
    #   omit_obvious_property_types, specify_nonobvious_property_types,
    #   lines_longer_than_80_chars, document_ignores, simplify_variable_pattern
    # Needs Dart 3.11+: initialize_in_field_declaration (3.13),
    #   simple_directive_paths (3.12), no_dynamic_casts and no_raw_types (3.13).

formatter:
  trailing_commas: preserve
```

Create `LICENSE`:

```text
MIT License

Copyright (c) 2026 Yevhenii Aleksiuk

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 5: Create the package manifests**

Create `packages/typed_graphql/pubspec.yaml`:

```yaml
name: typed_graphql
description: >-
  GraphQL for Dart, written from scratch and fully typed: the language, the type system, validation and the wire protocol, with diagnostics instead of exceptions.
version: 0.0.1
repository: https://github.com/4akloon/graphql_dart
issue_tracker: https://github.com/4akloon/graphql_dart/issues
topics: [graphql]

environment:
  sdk: ^3.13.0

dependencies:
  meta: ^1.15.0

dev_dependencies:
  test: ^1.31.0

resolution: workspace
```

Create `packages/typed_graphql_server/pubspec.yaml`:

```yaml
name: typed_graphql_server
description: >-
  A fully typed GraphQL server for Dart: a typed schema builder, the execution engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws and graphql-sse handlers.
version: 0.0.1
repository: https://github.com/4akloon/graphql_dart
issue_tracker: https://github.com/4akloon/graphql_dart/issues
topics: [graphql]

environment:
  sdk: ^3.13.0

dependencies:
  typed_graphql: ^0.0.1

dev_dependencies:
  test: ^1.31.0

resolution: workspace
```

Create `packages/typed_graphql_shelf/pubspec.yaml`:

```yaml
name: typed_graphql_shelf
description: >-
  The shelf adapter of typed_graphql_server: GraphQL over HTTP and WebSocket handlers for shelf, with an optional GraphiQL page in development.
version: 0.0.1
repository: https://github.com/4akloon/graphql_dart
issue_tracker: https://github.com/4akloon/graphql_dart/issues
topics: [graphql]

environment:
  sdk: ^3.13.0

dependencies:
  typed_graphql_server: ^0.0.1

dev_dependencies:
  test: ^1.31.0

resolution: workspace
```

Create `packages/typed_graphql_client/pubspec.yaml`:

```yaml
name: typed_graphql_client
description: >-
  A fully typed GraphQL client for Dart and Flutter: links, transports, a normalized cache and MockLink, for operations generated by typed_graphql_codegen.
version: 0.0.1
repository: https://github.com/4akloon/graphql_dart
issue_tracker: https://github.com/4akloon/graphql_dart/issues
topics: [graphql]

environment:
  sdk: ^3.13.0

dependencies:
  typed_graphql: ^0.0.1

dev_dependencies:
  test: ^1.31.0

resolution: workspace
```

Create `packages/typed_graphql_codegen/pubspec.yaml`:

```yaml
name: typed_graphql_codegen
description: >-
  The typed_graphql code generator and its CLI: Dart client code from .graphql operations and SDL-first server code, without the analyzer.
version: 0.0.1
repository: https://github.com/4akloon/graphql_dart
issue_tracker: https://github.com/4akloon/graphql_dart/issues
topics: [graphql]

environment:
  sdk: ^3.13.0

dependencies:
  typed_graphql: ^0.0.1

dev_dependencies:
  test: ^1.31.0

resolution: workspace
```

Create `packages/typed_graphql_builder/pubspec.yaml`:

```yaml
name: typed_graphql_builder
description: >-
  build_runner builders for typed_graphql: the client and SDL-first generators and the annotation front end for code-first servers.
version: 0.0.1
repository: https://github.com/4akloon/graphql_dart
issue_tracker: https://github.com/4akloon/graphql_dart/issues
topics: [graphql]

environment:
  sdk: ^3.13.0

dependencies:
  typed_graphql_codegen: ^0.0.1

dev_dependencies:
  test: ^1.31.0

resolution: workspace
```

Create `packages/typed_graphql_conformance/pubspec.yaml`:

```yaml
name: typed_graphql_conformance
description: >-
  Repository tool of typed_graphql: ported graphql-js suites, fuzzers and benchmarks. Never published.
publish_to: none

environment:
  sdk: ^3.13.0

dependencies:
  typed_graphql: any
  typed_graphql_builder: any
  typed_graphql_client: any
  typed_graphql_codegen: any
  typed_graphql_server: any
  typed_graphql_shelf: any

dev_dependencies:
  test: ^1.31.0

resolution: workspace
```

- [ ] **Step 6: Create the libraries**

Create `packages/typed_graphql/lib/typed_graphql.dart`:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: nothing is exported yet; see the package README.
library;
```

Create `packages/typed_graphql_server/lib/typed_graphql_server.dart`:

```dart
/// A fully typed GraphQL server for Dart: a typed schema builder, the execution
/// engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws
/// and graphql-sse handlers.
///
/// Under construction: nothing is exported yet; see the package README.
library;
```

Create `packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart`:

```dart
/// The shelf adapter of typed_graphql_server: GraphQL over HTTP and WebSocket
/// handlers for shelf, with an optional GraphiQL page in development.
///
/// Under construction: nothing is exported yet; see the package README.
library;
```

Create `packages/typed_graphql_client/lib/typed_graphql_client.dart`:

```dart
/// A fully typed GraphQL client for Dart and Flutter: links, transports, a
/// normalized cache and MockLink, for operations generated by
/// typed_graphql_codegen.
///
/// Under construction: nothing is exported yet; see the package README.
library;
```

Create `packages/typed_graphql_codegen/lib/typed_graphql_codegen.dart`:

```dart
/// The typed_graphql code generator and its CLI: Dart client code from .graphql
/// operations and SDL-first server code, without the analyzer.
///
/// Under construction: nothing is exported yet; see the package README.
library;
```

Create `packages/typed_graphql_builder/lib/typed_graphql_builder.dart`:

```dart
/// build_runner builders for typed_graphql: the client and SDL-first generators
/// and the annotation front end for code-first servers.
///
/// Under construction: nothing is exported yet; see the package README.
library;
```

Create `packages/typed_graphql_conformance/lib/typed_graphql_conformance.dart`:

```dart
/// Repository tool of typed_graphql: ported graphql-js suites, fuzzers and
/// benchmarks. Never published.
///
/// Under construction: nothing is exported yet; see the package README.
library;
```

- [ ] **Step 7: Create the READMEs**

Create `packages/typed_graphql/README.md`. Task 13 replaces it with the full README.

```markdown
# typed_graphql

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-core-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**GraphQL for Dart, written from scratch and fully typed: the language, the type system, validation and the wire protocol, with diagnostics instead of exceptions.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: skeleton.** The diagnostics model and the protocol data types
> arrive in stage M1 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md);
> nothing is exported yet.

## License

MIT — see [LICENSE](LICENSE).
```

Create `packages/typed_graphql_server/README.md`:

```markdown
# typed_graphql_server

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-server-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**A fully typed GraphQL server for Dart: a typed schema builder, the execution engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws and graphql-sse handlers.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: skeleton.** The package exists so the workspace, CI and the
> code rules cover it from the start. Its code arrives in stage M5 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.

Planned: `SchemaBuilder` and `ExecutableSchema` (M5), the `GraphQLServer` pipeline with APQ, trusted documents and DataLoader (M6), and the GraphQL over HTTP, graphql-ws and graphql-sse handlers (M7).

## License

MIT — see [LICENSE](LICENSE).
```

Create `packages/typed_graphql_shelf/README.md`:

```markdown
# typed_graphql_shelf

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-adapter-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**The shelf adapter of typed_graphql_server: GraphQL over HTTP and WebSocket handlers for shelf, with an optional GraphiQL page in development.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: skeleton.** The package exists so the workspace, CI and the
> code rules cover it from the start. Its code arrives in stage M7 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.

Planned (M7): a `shelf` `Handler` for GraphQL over HTTP, graphql-ws over WebSocket and graphql-sse, and a GraphiQL page you switch on in development.

## License

MIT — see [LICENSE](LICENSE).
```

Create `packages/typed_graphql_client/README.md`:

```markdown
# typed_graphql_client

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-client-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**A fully typed GraphQL client for Dart and Flutter: links, transports, a normalized cache and MockLink, for operations generated by typed_graphql_codegen.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: skeleton.** The package exists so the workspace, CI and the
> code rules cover it from the start. Its code arrives in stage M11 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.

Planned: `GraphQLClient`, the sealed `GraphQLResponse`, links for HTTP, WebSocket and SSE, and `MockLink` (M11); the normalized cache and `watchQuery` (M12).

## License

MIT — see [LICENSE](LICENSE).
```

Create `packages/typed_graphql_codegen/README.md`:

```markdown
# typed_graphql_codegen

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-codegen-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**The typed_graphql code generator and its CLI: Dart client code from .graphql operations and SDL-first server code, without the analyzer.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: skeleton.** The package exists so the workspace, CI and the
> code rules cover it from the start. Its code arrives in stages M8 and M10 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.

Planned: the client generator and its CLI (M10), then the SDL-first server generator (M8). It does not depend on `analyzer`.

## License

MIT — see [LICENSE](LICENSE).
```

Create `packages/typed_graphql_builder/README.md`:

```markdown
# typed_graphql_builder

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-builder-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**build_runner builders for typed_graphql: the client and SDL-first generators and the annotation front end for code-first servers.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: skeleton.** The package exists so the workspace, CI and the
> code rules cover it from the start. Its code arrives in stage M9 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.

Planned (M9): `build_runner` builders around typed_graphql_codegen, and the annotation front end that turns annotated Dart classes into a schema. It is the only package that depends on `analyzer`.

## License

MIT — see [LICENSE](LICENSE).
```

Create `packages/typed_graphql_conformance/README.md`:

```markdown
# typed_graphql_conformance

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-tool-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**Repository tool of typed_graphql: ported graphql-js suites, fuzzers and benchmarks. Never published.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: skeleton.** The package exists so the workspace, CI and the
> code rules cover it from the start. Its code arrives in stage M2 of the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.

Planned: the graphql-js v17 suites, ported with a mapping table (from M2), round-trip fuzzing of the parser and printer, and benchmarks.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 8: Create the changelog, then copy the shared files into every package**

Create `packages/typed_graphql/CHANGELOG.md`:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
```

Copy the root `LICENSE`, this changelog and the pubspec test into the other six packages. All three files are identical in every package.

```bash
cp LICENSE packages/typed_graphql/LICENSE
for p in typed_graphql_server typed_graphql_shelf typed_graphql_client typed_graphql_codegen typed_graphql_builder typed_graphql_conformance; do
  mkdir -p "packages/$p/test"
  cp LICENSE "packages/$p/LICENSE"
  cp packages/typed_graphql/CHANGELOG.md "packages/$p/CHANGELOG.md"
  cp packages/typed_graphql/test/pubspec_test.dart "packages/$p/test/pubspec_test.dart"
done
```

- [ ] **Step 9: Run the green check**

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages
dart analyze --fatal-infos
for p in packages/*/; do (cd "$p" && dart test) || exit 1; done
```

Expected:
- `pub get` resolves the workspace ("Got dependencies!");
- the formatter reports "0 changed";
- `dart analyze` prints "No issues found!";
- each of the seven packages ends with `+2: All tests passed!`.

- [ ] **Step 10: Commit**

```bash
git add -A pubspec.yaml analysis_options.yaml LICENSE packages
git commit -q -m "build: replace the old package with the typed_graphql workspace"
```

- [ ] **Step 11: Check that the six publishable packages would publish**

```sh
for p in typed_graphql typed_graphql_server typed_graphql_shelf typed_graphql_client typed_graphql_codegen typed_graphql_builder; do
  (cd "packages/$p" && dart pub publish --dry-run) || exit 1
done
```

Expected: every package ends with "Package has 0 warnings.". This is a dry run, so nothing is uploaded. `typed_graphql_conformance` has `publish_to: none` and is skipped.

### Task 2: Blanked code and the nesting meter

The code rules read Dart as text. `BlankedCode` makes that safe: it replaces comments and the contents of strings with spaces, so a regular expression never matches inside them. Line numbers and columns stay those of the source. `NestingMeter` uses it to find control blocks nested too deep.

**Files:**
- Create: `test/quality/blanked_code.dart`, `test/quality/nesting_meter.dart`
- Test: `test/quality/blanked_code_test.dart`, `test/quality/nesting_meter_test.dart`

**Interfaces:**
- Consumes: the workspace from Task 1. The root `pubspec.yaml` has `test` as a dev dependency.
- Produces:
  - `final class BlankedCode`, with:
    - `BlankedCode(String source)`;
    - `final List<String> lines`: the blanked lines;
    - `late final List<int> depths`: how many of `(`, `[` and `{` are open at the start of each line;
    - `Iterable<(int, String)> unitsFrom(int from)`: every code unit from line `from` on, with its line index, and a `\n` ending every line;
    - `static int bracketBalance(String text)`.
  - `final class NestingMeter(final BlankedCode code)`, with `List<int> linesDeeperThan(int limit)`: the 0-based indexes of the lines where a control block opens deeper than `limit`.

- [ ] **Step 1: Write the failing test for `BlankedCode`**

Create `test/quality/blanked_code_test.dart`:

```dart
import 'package:test/test.dart';

import 'blanked_code.dart';

void main() {
  test('blanks comments and keeps the quotes of strings', () {
    final code = BlankedCode(
      "final a = 'x { y'; // a { comment\n"
      '/* block /* nested */ still */ final b = "z";\n',
    );
    expect(code.lines, [
      "final a = '     ';${' ' * 15}",
      '${' ' * 31}final b = " ";',
      '',
    ]);
  });

  test('blanks interpolations, with the strings inside them', () {
    final code = BlankedCode(
      r"""final a = 'say ${'}'} and ${{1}.length} $b';""",
    );
    expect(code.lines.single, "final a = '${' ' * 31}';");
  });

  test('reads raw and multi-line strings', () {
    final code = BlankedCode("final a = r'\\';\nfinal b = '''\n{\n''';\n");
    expect(code.lines, [
      "final a = r' ';",
      "final b = '''",
      ' ',
      "''';",
      '',
    ]);
  });

  test('counts the brackets open at the start of each line', () {
    final code = BlankedCode('void f() {\n  g([\n    1,\n  ]);\n}\n');
    expect(code.depths, [0, 1, 3, 3, 1, 0]);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `dart test test/quality/blanked_code_test.dart`
Expected: FAIL with `Error when reading 'test/quality/blanked_code.dart': No such file or directory`.

- [ ] **Step 3: Implement `BlankedCode`**

Create `test/quality/blanked_code.dart`:

```dart
/// The text of a Dart library with every comment and the contents of
/// every string replaced by spaces, so that the rules can read the code
/// with regular expressions and count brackets.
///
/// Line breaks and the quotes of strings stay, so a line number and a
/// column of the blanked text are those of the source. An interpolation
/// (`${...}`) is part of its string and is blanked with it.
final class BlankedCode {
  /// Blanks [source].
  BlankedCode(String source) : lines = _Blanker(source).blank().split('\n');

  /// The blanked lines, in order.
  final List<String> lines;

  // `late`: most files are read by rules that never look at brackets.
  /// How many `(`, `[` and `{` are open at the start of each line.
  late final List<int> depths = _depths();

  List<int> _depths() {
    final result = <int>[];
    var depth = 0;
    for (final line in lines) {
      result.add(depth);
      depth += bracketBalance(line);
    }
    return result;
  }

  /// Every code unit from line [from] on, with the index of its line; a
  /// `\n` ends every line.
  Iterable<(int, String)> unitsFrom(int from) sync* {
    for (var line = from; line < lines.length; line++) {
      for (final unit in '${lines[line]}\n'.split('')) {
        yield (line, unit);
      }
    }
  }

  /// The number of `(`, `[` and `{` in [text] minus the number of `)`,
  /// `]` and `}`.
  static int bracketBalance(String text) {
    var balance = 0;
    for (var i = 0; i < text.length; i++) {
      balance += switch (text[i]) {
        '(' || '[' || '{' => 1,
        ')' || ']' || '}' => -1,
        _ => 0,
      };
    }
    return balance;
  }
}

/// The state machine behind [BlankedCode]: code, comments, strings and
/// the interpolations inside strings.
final class _Blanker(final String source) {
  final StringBuffer _out = StringBuffer();

  /// For every string being read, innermost last: its quote (`'`, `"`,
  /// `'''` or `"""`), and whether it is raw.
  final List<({String quote, bool isRaw})> _strings = [];

  /// For every interpolation being read, innermost last: how many `{` it
  /// has open.
  final List<int> _interpolations = [];

  int _at = 0;

  /// [source] with comments and string contents blanked.
  String blank() {
    while (_at < source.length) {
      if (_strings.length > _interpolations.length) {
        _readString();
      } else {
        _readCode();
      }
    }
    return _out.toString();
  }

  void _readCode() {
    if (source.startsWith('//', _at)) {
      _skipWhile((unit) => unit != '\n');
    } else if (source.startsWith('/*', _at)) {
      _skipBlockComment();
    } else if (_quoteAt(_at) case final quote?) {
      final isRaw = _at > 0 && source[_at - 1] == 'r' && !_isNamePart(_at - 2);
      _strings.add((quote: quote, isRaw: isRaw));
      _keep(quote.length);
    } else {
      _readCodeUnit();
    }
  }

  void _readCodeUnit() {
    final unit = source[_at];
    if (_interpolations.isNotEmpty && unit == '{') {
      _interpolations.last++;
    } else if (_interpolations.isNotEmpty && unit == '}') {
      if (_interpolations.last == 0) {
        _interpolations.removeLast();
        _blank(1);
        return;
      }
      _interpolations.last--;
    }
    _keep(1);
  }

  void _readString() {
    final (:quote, :isRaw) = _strings.last;
    if (source.startsWith(quote, _at)) {
      _strings.removeLast();
      _keep(quote.length);
    } else if (!isRaw && source[_at] == r'\') {
      _blank(2);
    } else if (!isRaw && source.startsWith(r'${', _at)) {
      _interpolations.add(0);
      _blank(2);
    } else {
      _blank(1);
    }
  }

  /// The quote that opens a string at [offset], or null.
  String? _quoteAt(int offset) {
    for (final quote in const ["'''", '"""', "'", '"']) {
      if (source.startsWith(quote, offset)) {
        return quote;
      }
    }
    return null;
  }

  bool _isNamePart(int offset) =>
      offset >= 0 && RegExp(r'[\w$]').hasMatch(source[offset]);

  void _skipBlockComment() {
    var depth = 0;
    do {
      if (source.startsWith('/*', _at)) {
        depth++;
        _blank(2);
      } else if (source.startsWith('*/', _at)) {
        depth--;
        _blank(2);
      } else {
        _blank(1);
      }
    } while (depth > 0 && _at < source.length);
  }

  void _skipWhile(bool Function(String unit) test) {
    while (_at < source.length && test(source[_at])) {
      _blank(1);
    }
  }

  /// Copies [count] code units, or blanks them inside an interpolation.
  void _keep(int count) {
    final end = (_at + count).clamp(0, source.length);
    if (_interpolations.isEmpty) {
      _out.write(source.substring(_at, end));
    } else {
      _blankRange(end);
    }
    _at = end;
  }

  void _blank(int count) {
    _blankRange((_at + count).clamp(0, source.length));
  }

  void _blankRange(int end) {
    for (; _at < end; _at++) {
      _out.write(source[_at] == '\n' ? '\n' : ' ');
    }
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `dart test test/quality/blanked_code_test.dart`
Expected: `+4: All tests passed!`

- [ ] **Step 5: Write the failing test for `NestingMeter`**

Create `test/quality/nesting_meter_test.dart`:

```dart
import 'package:test/test.dart';

import 'blanked_code.dart';
import 'nesting_meter.dart';

void main() {
  List<int> deeperThan3(String body) => NestingMeter(
    BlankedCode('void f() {\n$body}\n'),
  ).linesDeeperThan(3);

  test('counts if, for, while, switch and try', () {
    expect(
      deeperThan3(
        '  for (;;) {\n'
        '    while (true) {\n'
        '      try {\n'
        '        if (a) {\n'
        '        }\n'
        '      } on E catch (e) {\n'
        '      }\n'
        '    }\n'
        '  }\n',
      ),
      [4],
    );
  });

  test('does not count an else-if chain as deeper', () {
    expect(
      deeperThan3(
        '  for (;;) {\n'
        '    if (a) {\n'
        '      if (b) {\n'
        '      } else if (c) {\n'
        '      } else {\n'
        '      }\n'
        '    }\n'
        '  }\n',
      ),
      isEmpty,
    );
  });

  test('counts a switch expression but not closures or literals', () {
    expect(
      deeperThan3(
        '  for (;;) {\n'
        '    if (a) {\n'
        '      list.forEach((x) {\n'
        '        final m = {1: 2};\n'
        '        return switch (x) {\n'
        '          _ => () { if (y) {} },\n'
        '        };\n'
        '      });\n'
        '    }\n'
        '  }\n',
      ),
      [6],
    );
  });

  test('does not read a map pattern as a block', () {
    expect(
      deeperThan3(
        '  for (;;) {\n'
        '    if (a) {\n'
        "      if (m case {'k': 1}) {\n"
        '      }\n'
        '    }\n'
        '  }\n',
      ),
      isEmpty,
    );
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `dart test test/quality/nesting_meter_test.dart`
Expected: FAIL, because `nesting_meter.dart` does not exist.

- [ ] **Step 7: Implement `NestingMeter`**

Create `test/quality/nesting_meter.dart`:

```dart
import 'blanked_code.dart';

/// Measures how deeply control blocks nest: the `{` of `if`, `else`,
/// `for`, `while`, `do`, `switch` (statement or expression), `try`,
/// `catch`, `on` and `finally`.
///
/// Other braces (bodies, closures, collection literals, patterns) do not
/// count, but a control block inside a closure counts on top of the
/// blocks around the closure.
final class NestingMeter(final BlankedCode code) {
  static final RegExp _controlHead = RegExp(
    r'^(?:if|else|for|await\s+for|while|do|switch|try|catch|on|finally)\b',
  );

  static final RegExp _switchHead = RegExp(r'\bswitch\s*\(');

  /// The index of every line where a control block opens deeper than
  /// [limit], in file order.
  List<int> linesDeeperThan(int limit) {
    final found = <int>[];
    final frames = [_Frame(isControl: false)];
    for (final (line, unit) in code.unitsFrom(0)) {
      final frame = frames.last;
      if (unit == '{') {
        frames.add(_Frame(isControl: _isControl(frame)));
        frame.endStatement();
        if (frames.where((frame) => frame.isControl).length > limit) {
          found.add(line);
        }
      } else if (unit == '}' && frames.length > 1) {
        frames.removeLast();
        frames.last.endStatement();
      } else {
        frame.read(unit);
      }
    }
    return {...found}.toList();
  }

  /// Whether the `{` read next in [frame] opens a control block.
  bool _isControl(_Frame frame) {
    final head = frame.statement.trim();
    if (frame.parentheses == 0 && _controlHead.hasMatch(head)) {
      return true;
    }
    final switchAt = head.lastIndexOf(_switchHead);
    return switchAt >= 0 &&
        head.endsWith(')') &&
        BlankedCode.bracketBalance(head.substring(switchAt)) == 0;
  }
}

/// The statement being read inside one `{`, and how many `(` and `[` it
/// has open.
final class _Frame({required final bool isControl}) {
  final StringBuffer _statement = StringBuffer();

  int parentheses = 0;

  String get statement => _statement.toString();

  /// Adds [unit] to the statement; a `;` outside brackets ends it.
  void read(String unit) {
    parentheses += switch (unit) {
      '(' || '[' => 1,
      ')' || ']' => -1,
      _ => 0,
    };
    if (unit == ';' && parentheses == 0) {
      _statement.clear();
    } else {
      _statement.write(unit);
    }
  }

  /// Starts a new statement after a block, unless the block was inside
  /// brackets (a closure argument, a map pattern).
  void endStatement() {
    if (parentheses == 0) {
      _statement.clear();
    }
  }
}
```

- [ ] **Step 8: Run the green check**

Run the commands in "The green check" (with `packages test` in the format command from now on).
Expected:
- the root `dart test` ends with `+8: All tests passed!`;
- every package ends with `+2: All tests passed!`;
- format and analyze are clean.

- [ ] **Step 9: Commit**

```bash
git add test/quality
git commit -q -m "test(quality): add the blanked-code reader and the nesting meter"
```

### Task 3: Declaration scanner

The scanner finds the declarations of a file: top-level types, their members, and top-level functions, each with its line range. For callables it also counts the parameters. The size and parameter rules of Task 4 read these.

**Files:**
- Create: `test/quality/declaration.dart`, `test/quality/signature.dart`, `test/quality/declaration_scanner.dart`
- Test: `test/quality/signature_test.dart`, `test/quality/declaration_scanner_test.dart`

**Interfaces:**
- Consumes (Task 2): `BlankedCode(String source)`, `.lines`, `.depths`, `.unitsFrom(int)`, `BlankedCode.bracketBalance(String)`.
- Produces:
  - `final class Declaration(final String name, final int start, final int end, {final bool isCallable = false, final bool isConstructor = false, final int parameterCount = 0})`, with `int get length` (`end - start + 1`) and `int get lineNumber` (`start + 1`). `start` and `end` are 0-based line indexes, both inclusive.
  - `final class Signature(String text)`, with `bool get isCallable`, `String get name` and `int get parameterCount`. A primary constructor body `this` is named `this`.
  - `final class DeclarationScanner(final BlankedCode code)`, with:
    - `List<({Declaration type, String header})> get types`;
    - `List<Declaration> get members`: members of every type, indented exactly two spaces; enum values are not members;
    - `List<Declaration> get functions`: top-level callables.

- [ ] **Step 1: Write the failing test for `Signature`**

Create `test/quality/signature_test.dart`:

```dart
import 'package:test/test.dart';

import 'signature.dart';

void main() {
  test('reads the name and the parameters of a method', () {
    final signature = Signature('  int add(int a, int b) {');
    expect(signature.isCallable, isTrue);
    expect(signature.name, 'add');
    expect(signature.parameterCount, 2);
  });

  test('counts named and optional parameters with their defaults', () {
    expect(
      Signature('  void f(int a, {required int b, List<int> c = const []}) {')
          .parameterCount,
      3,
    );
    expect(
      Signature('  void f(int a, [int b = 0, int c = 1, int d]) {')
          .parameterCount,
      4,
    );
  });

  test('counts parameters over several lines with a trailing comma', () {
    expect(
      Signature(
        '  void f(\n'
        '    Map<String, int> a,\n'
        '    void Function(int x, int y) b, {\n'
        '    int c = 1,\n'
        '  }) {',
      ).parameterCount,
      3,
    );
  });

  test('reads getters, setters, operators and generic methods', () {
    expect(Signature('  int get size => 1;').name, 'size');
    expect(Signature('  set size(int value) {').name, 'size=');
    expect(
      Signature('  bool operator ==(Object other) =>').name,
      'operator ==',
    );
    expect(Signature('  void operator []=(int i, int v) {').isCallable, isTrue);
    expect(Signature('  T first<T>(List<T> items) {').name, 'first');
    expect(Signature('  (int, int) pair() =>').name, 'pair');
  });

  test('reads a primary constructor body as this', () {
    expect(Signature('  this : assert(x > 0);').name, 'this');
    expect(Signature('  this {').name, 'this');
  });

  test('a field is not callable, even with a closure or a record type', () {
    for (final line in [
      '  static final RegExp pattern = RegExp(r"x");',
      '  final List<({int a, int b})> items = [];',
      '  final int Function(int) twice = (x) => x * 2;',
      '  static const values = {',
      '  final int count;',
    ]) {
      expect(Signature(line).isCallable, isFalse, reason: line);
    }
    expect(Signature('  final List<({int a})> items = [];').name, 'items');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `dart test test/quality/signature_test.dart`
Expected: FAIL, because `signature.dart` does not exist.

- [ ] **Step 3: Implement `Signature`**

Create `test/quality/signature.dart`:

```dart
/// The signature of one declaration, read from its blanked text: whether
/// it is callable, its name and how many parameters it takes.
final class Signature(String text) {
  /// The parameter list of a function type, replaced by `Function` so its
  /// parentheses and commas are not read as the declaration's.
  static final RegExp _functionType = RegExp(
    r'\bFunction\s*\((?:[^()]|\([^()]*\))*\)',
  );

  /// `operator ==(`, `operator []=(`: the symbol is replaced so its `=` is
  /// not read as an assignment.
  static final RegExp _operator = RegExp(r'\boperator\s*([^\s(]+)\s*\(');

  /// The `(` of a parameter list: it follows a name or type parameters.
  static final RegExp _parameterList = RegExp(r'[\w$>]\s*\(');

  static final RegExp _accessor = RegExp(r'\b(get|set)\s+([A-Za-z_$][\w$]*)');

  static final RegExp _trailingName = RegExp(
    r'([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?)$',
  );

  /// The operator symbol, such as `==`; null when this is no operator.
  final String? _operatorSymbol = _operator.firstMatch(text)?[1];

  /// The text with function types and operator symbols replaced.
  final String _text = text
      .replaceAll(_functionType, 'Function')
      .replaceAll(_operator, 'operator x(');

  // `late`: both are derived from [_text], which a field initializer
  // cannot read.
  late final String _firstLine = _text.split('\n').first;

  /// The offset in the first line of what makes the declaration callable:
  /// the `(` of its parameters, its `=>`, or a `{` that ends the line;
  /// -1 when there is none.
  late final int _marker = _firstOf([
    _parameterList.firstMatch(_firstLine)?.end ?? 0,
    _firstLine.indexOf('=>') + 1,
    if (_firstLine.trimRight().endsWith('{')) _firstLine.lastIndexOf('{') + 1,
  ]);

  /// Whether this is a method, getter, setter, operator, constructor or
  /// function rather than a field or a variable.
  bool get isCallable {
    final assignment = _assignmentIn(_firstLine);
    return _marker >= 0 && (assignment < 0 || assignment > _marker);
  }

  /// The declared name: `run`, `Type.named`, `operator ==`, `value=` for a
  /// setter, `this` for the body of a primary constructor.
  String get name {
    final head = _firstLine.substring(0, _nameEnd);
    if (_operatorSymbol case final symbol?) {
      return 'operator $symbol';
    }
    if (RegExp(r'^\s*this\b').hasMatch(head)) {
      return 'this';
    }
    if (_accessor.firstMatch(head) case final accessor?) {
      return accessor[1] == 'set' ? '${accessor[2]}=' : accessor[2]!;
    }
    final bare = _withoutTypeParameters(head);
    return _trailingName.firstMatch(bare)?[1] ?? head.trim();
  }

  /// Where the name ends in the first line: at the marker of a callable,
  /// at the `=` or `;` of a field.
  int get _nameEnd {
    if (isCallable) {
      return _marker;
    }
    final assignment = _assignmentIn(_firstLine);
    final semicolon = _firstLine.indexOf(';');
    return assignment >= 0
        ? assignment
        : (semicolon >= 0 ? semicolon : _firstLine.length);
  }

  /// The number of parameters in the parameter list; 0 when there is
  /// none.
  int get parameterCount {
    final match = _parameterList.firstMatch(_firstLine);
    return match == null || match.end - 1 > _marker
        ? 0
        : _countItems(match.end);
  }

  /// The items of the list that starts at [from], up to its `)`. A `{`
  /// or `[` that opens a group of named or optional parameters is not a
  /// bracket; the group is always last.
  int _countItems(int from) {
    var depth = 0;
    var count = 0;
    var hasItem = false;
    for (var i = from; i < _text.length; i++) {
      final unit = _text[i];
      if (depth == 0 && ')]}'.contains(unit)) {
        break;
      }
      if (depth == 0 && unit == ',') {
        count++;
        hasItem = false;
      } else if (unit.trim().isNotEmpty && (hasItem || !'{['.contains(unit))) {
        hasItem = true;
        depth += _bracketChange(unit);
      }
    }
    return count + (hasItem ? 1 : 0);
  }

  static int _bracketChange(String unit) => switch (unit) {
    '(' || '[' || '{' || '<' => 1,
    ')' || ']' || '}' || '>' => -1,
    _ => 0,
  };

  /// The offset of the first `=` in [line] outside brackets that is an
  /// assignment (not `==`, `=>`, `<=`, `>=` or `!=`); -1 when there is
  /// none.
  static int _assignmentIn(String line) {
    var depth = 0;
    for (var i = 0; i < line.length; i++) {
      final before = i > 0 ? line[i - 1] : ' ';
      final after = i + 1 < line.length ? line[i + 1] : ' ';
      if (depth == 0 &&
          line[i] == '=' &&
          !'=!<>'.contains(before) &&
          !'=>'.contains(after)) {
        return i;
      }
      depth += _bracketChange(line[i]);
    }
    return -1;
  }

  /// The smallest of [offsets] above 0, minus one; -1 when none is.
  static int _firstOf(List<int> offsets) {
    final found = [
      for (final offset in offsets)
        if (offset > 0) offset,
    ];
    return found.isEmpty ? -1 : found.reduce((a, b) => a < b ? a : b) - 1;
  }

  /// [text] trimmed, without a trailing `<...>`.
  static String _withoutTypeParameters(String text) {
    final trimmed = text.trimRight();
    var depth = 0;
    for (var i = trimmed.length - 1; i >= 0 && trimmed.endsWith('>'); i--) {
      depth += switch (trimmed[i]) {
        '>' => 1,
        '<' => -1,
        _ => 0,
      };
      if (depth == 0) {
        return trimmed.substring(0, i).trimRight();
      }
    }
    return trimmed;
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `dart test test/quality/signature_test.dart`
Expected: `+6: All tests passed!`

- [ ] **Step 5: Write the failing test for `DeclarationScanner`**

Create `test/quality/declaration_scanner_test.dart`:

```dart
import 'package:test/test.dart';

import 'blanked_code.dart';
import 'declaration_scanner.dart';

void main() {
  DeclarationScanner scan(String source) =>
      DeclarationScanner(BlankedCode(source));

  test('finds types, their members and top-level functions', () {
    final scanner = scan(
      'final class A(final int x) {\n'
      '  this;\n'
      '\n'
      '  /// Doc.\n'
      '  @override\n'
      '  int get y =>\n'
      '      x + 1;\n'
      '  static const z = 1;\n'
      '}\n'
      '\n'
      'void main() {}\n'
      'int helper(int a) => a;\n',
    );
    expect([for (final t in scanner.types) t.type.name], ['A']);
    expect(
      [for (final m in scanner.members) (m.name, m.start, m.end)],
      [('A.this', 1, 1), ('A.y', 5, 6), ('A.z', 7, 7)],
    );
    expect([for (final f in scanner.functions) f.name], ['main', 'helper']);
  });

  test('skips the parameters of a primary constructor and enum values', () {
    final scanner = scan(
      'enum E(\n'
      '  final int id,\n'
      ') {\n'
      '  a(1),\n'
      '  b(2);\n'
      '\n'
      '  bool get isA => this == a;\n'
      '}\n',
    );
    expect([for (final m in scanner.members) m.name], ['E.isA']);
  });

  test('tells constructors from methods and fields', () {
    final members = scan(
      'class A {\n'
      '  A(int a);\n'
      '  A.named(int a);\n'
      '  factory A.make() => A(1);\n'
      '  final List<({int a, int b})> items = [];\n'
      '  final void Function(int a) f = print;\n'
      '  void run() {}\n'
      '}\n',
    ).members;
    expect(
      [for (final m in members) (m.name, m.isCallable, m.isConstructor)],
      [
        ('A.new', true, true),
        ('A.named', true, true),
        ('A.make', true, true),
        ('A.items', false, false),
        ('A.f', false, false),
        ('A.run', true, false),
      ],
    );
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `dart test test/quality/declaration_scanner_test.dart`
Expected: FAIL, because `declaration_scanner.dart` does not exist.

- [ ] **Step 7: Implement `Declaration` and `DeclarationScanner`**

Create `test/quality/declaration.dart`:

```dart
/// A declaration found by [DeclarationScanner]: a top-level type or
/// function, or a member of a type.
final class Declaration(
  /// The name: `Type`, `function`, or `Type.member` for a member (`Type.new`
  /// for an unnamed constructor, `Type.this` for the body of a primary
  /// constructor).
  final String name,

  /// The index of the first line, from 0; annotations and doc comments
  /// are not part of it.
  final int start,

  /// The index of the last line.
  final int end, {

  /// For a member, whether it is a method, getter, setter, operator or
  /// constructor rather than a field or an enum value.
  final bool isCallable = false,

  /// For a member, whether it is a constructor.
  final bool isConstructor = false,

  /// The number of parameters of a callable member; 0 for the rest.
  final int parameterCount = 0,
}) {
  /// Creates a declaration.
  this;

  /// The number of lines, both ends included.
  int get length => end - start + 1;

  /// The line number people count, from 1.
  int get lineNumber => start + 1;
}
```

Create `test/quality/declaration_scanner.dart`:

```dart
import 'blanked_code.dart';
import 'declaration.dart';
import 'signature.dart';

/// Finds the declarations of a formatted Dart library by its brackets.
///
/// A type starts on a line in the first column with `class`, `mixin`,
/// `enum`, `extension` or `typedef`; its body is the first `{` outside
/// brackets after that. A member starts on a line inside the body where
/// exactly one bracket is open and the indent is two spaces, and ends
/// before the next such line;
/// annotations and doc comments are not part of it. False negatives are
/// accepted, a false positive is a bug of this class.
final class DeclarationScanner(final BlankedCode code) {
  static final RegExp _typeHeader = RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
    r'(class|mixin|enum|extension\s+type|extension|typedef)\s+'
    r'(?:const\s+)?([A-Za-z_$][\w$]*)',
  );

  static final RegExp _directive = RegExp(
    r'^(?:import|export|part|library)\b',
  );

  // `late`: computed once, on the first use of [types] or [members].
  late final List<_TypeSpan> _spans = [
    for (var i = 0; i < code.lines.length; i++)
      if (_typeHeader.firstMatch(code.lines[i]) case final header?)
        _spanOf(header, i),
  ];

  /// The top-level types, in file order, each with the header text up to
  /// its body.
  List<({Declaration type, String header})> get types => [
    for (final span in _spans)
      (
        type: Declaration(span.name, span.start, span.close ?? span.open),
        header: code.lines.sublist(span.start, span.open + 1).join('\n'),
      ),
  ];

  /// The members of every type, in file order; the values of an enum are
  /// not members.
  List<Declaration> get members => [
    for (final span in _spans) ..._membersOf(span),
  ];

  /// The top-level functions, getters and setters, in file order.
  List<Declaration> get functions => [
    for (var i = 0; i < code.lines.length; i++)
      if (_functionAt(i) case final name?) Declaration(name, i, i),
  ];

  /// The span of the type whose [header] is on line [start].
  _TypeSpan _spanOf(RegExpMatch header, int start) {
    final name = header[2]!;
    final isEnum = header[1] == 'enum';
    int? open;
    var depth = 0;
    for (final (line, unit) in code.unitsFrom(start)) {
      if (open == null && depth == 0 && unit == ';') {
        return _TypeSpan(name, start, line, null, isEnum: isEnum);
      }
      if (open == null && depth == 0 && unit == '{') {
        open = line;
      }
      depth += BlankedCode.bracketBalance(unit);
      if (open != null && depth == 0) {
        return _TypeSpan(name, start, open, line, isEnum: isEnum);
      }
    }
    return _TypeSpan(name, start, open ?? start, null, isEnum: isEnum);
  }

  List<Declaration> _membersOf(_TypeSpan span) {
    final close = span.close;
    if (close == null) {
      return const [];
    }
    final starts = [
      for (var i = _firstMemberLine(span); i < close; i++)
        if (_isMemberLevel(i)) i,
    ];
    return [
      for (var n = 0; n < starts.length; n++)
        if (!code.lines[starts[n]].trimLeft().startsWith('@'))
          _member(
            span.name,
            starts[n],
            _lastCodeLine(
              starts[n],
              n + 1 < starts.length ? starts[n + 1] : close,
            ),
          ),
    ];
  }

  /// The first line of [span]'s body after its enum values, if any.
  int _firstMemberLine(_TypeSpan span) {
    if (!span.isEnum) {
      return span.open + 1;
    }
    for (var i = span.open; i < (span.close ?? span.open); i++) {
      if (code.lines[i].trimRight().endsWith(';') && code.depths[i + 1] == 1) {
        return i + 1;
      }
    }
    return span.close ?? span.open;
  }

  /// Whether a member starts on [line]: one bracket is open, the line is
  /// indented by two spaces as `dart format` indents members, and it does
  /// not close a bracket.
  bool _isMemberLevel(int line) {
    final text = code.lines[line];
    return code.depths[line] == 1 &&
        text.startsWith('  ') &&
        !text.startsWith(RegExp(r'   |  [)\]}]')) &&
        text.trim().isNotEmpty;
  }

  /// The last line before [next] that has code.
  int _lastCodeLine(int start, int next) {
    var end = next - 1;
    while (end > start && code.lines[end].trim().isEmpty) {
      end--;
    }
    return end;
  }

  Declaration _member(String type, int start, int end) {
    final signature = Signature(code.lines.sublist(start, end + 1).join('\n'));
    final name = signature.name;
    final isConstructor =
        name == type ||
        name == 'this' ||
        name.startsWith('$type.') ||
        code.lines[start].trimLeft().startsWith('factory ');
    final member = name == type ? 'new' : name.replaceFirst('$type.', '');
    return Declaration(
      '$type.$member',
      start,
      end,
      isCallable: signature.isCallable,
      isConstructor: isConstructor,
      parameterCount: signature.parameterCount,
    );
  }

  /// The name of the top-level function that starts on line [index], or
  /// null when none does.
  String? _functionAt(int index) {
    final line = code.lines[index];
    if (code.depths[index] != 0 ||
        line.trim().isEmpty ||
        line.startsWith(RegExp(r'[\s@)\]}]')) ||
        _directive.hasMatch(line) ||
        _typeHeader.hasMatch(line)) {
      return null;
    }
    final signature = Signature(line);
    return signature.isCallable ? signature.name : null;
  }
}

/// Where a type sits: its header starts on [start], its body opens on
/// [open] and closes on [close] (null without a body).
final class _TypeSpan(
  final String name,
  final int start,
  final int open,
  final int? close, {
  required final bool isEnum,
});
```

- [ ] **Step 8: Run the green check**

Expected: the root `dart test` ends with `+17: All tests passed!`, and every package with `+2`.

- [ ] **Step 9: Commit**

```bash
git add test/quality
git commit -q -m "test(quality): add the declaration scanner"
```

### Task 4: Code rules and the workspace ratchet

**Files:**
- Create: `test/quality/code_rules.dart`, `test/quality/workspace_files.dart`
- Test: `test/quality/code_rules_fixtures_test.dart`, `test/quality/code_rules_test.dart`

**Interfaces:**
- Consumes:
  - Task 2: `BlankedCode`, `NestingMeter(code).linesDeeperThan(int)`.
  - Task 3: `DeclarationScanner(code).types`, `.members`, `.functions`, and `Declaration`.
- Produces:
  - `final class CodeRules`:
    - `const CodeRules()`;
    - constants `libFileLimit = 300`, `testFileLimit = 500`, `methodLimit = 40`, `parameterLimit = 5`, `nestingLimit = 3`;
    - `List<String> violations(String path, String content)`: each violation as `path:line: what is wrong`;
    - `int? oversizedFile(String path, String content)`: the line count when over the limit, else null;
    - `Map<String, int> longMethods(String path, String content)`: keyed `path#Type.member`, for `lib/` files only;
    - paths may use `\` or `/`.
  - `final class WorkspaceFiles(final String root)`, with `Map<String, String> read()`. It reads `packages/*/{lib,bin,test,tool}` and the root `test/`, keyed by `/`-separated paths from the root, in path order.
  - The ratchet `code_rules_test.dart`: one permanent exemption (`diagnostic_code.dart`, created in Task 7) and two empty allowlists, which may only ever shrink.

- [ ] **Step 1: Write the failing fixture tests**

Create `test/quality/code_rules_fixtures_test.dart`:

```dart
import 'package:test/test.dart';

import 'code_rules.dart';

/// Every rule of [CodeRules] on a small file that breaks it, and on one
/// that keeps it.
void main() {
  const rules = CodeRules();
  const libPath = 'packages/p/lib/src/a.dart';
  const testPath = 'packages/p/test/a_test.dart';

  List<String> violations(String path, String content) =>
      rules.violations(path, content);

  /// A class `A` whose body is [body].
  String classWith(String body) => '/// A.\nfinal class A {\n$body}\n';

  group('pattern rules', () {
    test('a clean file has no violations', () {
      expect(
        violations(libPath, classWith('  int get x => 1;\n')),
        isEmpty,
      );
    });

    test('part directives are rejected', () {
      expect(violations(libPath, "part 'b.dart';\n"), [
        '$libPath:1: a part directive; split into libraries',
      ]);
    });

    test('dynamic is rejected in code but not in comments or strings', () {
      expect(
        violations(testPath, 'void main() {\n  dynamic x;\n}\n'),
        ['$testPath:2: dynamic; use Object? or a real type'],
      );
      expect(
        violations(testPath, "// dynamic\nvoid main() => print('dynamic');\n"),
        isEmpty,
      );
    });

    test('a catch without on is rejected', () {
      expect(
        violations(
          testPath,
          'void main() {\n  try {\n  } catch (e) {\n  }\n}\n',
        ),
        ['$testPath:3: a catch without on; name the exception'],
      );
      expect(
        violations(
          testPath,
          'void main() {\n  try {\n  } on FormatException catch (e) {\n  }\n'
          '  f().catchError(g);\n}\n',
        ),
        isEmpty,
      );
    });

    test('top-level functions other than main are rejected', () {
      expect(
        violations(testPath, 'void main() {\n  int local() => 1;\n}\n'),
        isEmpty,
      );
      expect(violations(testPath, 'int helper() => 1;\n'), [
        '$testPath:1: the top-level function helper; put it in a class',
      ]);
      expect(violations(libPath, 'int get answer => 42;\n'), hasLength(1));
    });

    test('utils and helpers files are rejected in lib only', () {
      for (final path in [
        'packages/p/lib/src/utils.dart',
        'packages/p/lib/src/string_helpers.dart',
        'packages/p/lib/src/common/a.dart',
      ]) {
        expect(violations(path, ''), hasLength(1), reason: path);
      }
      expect(violations('packages/p/test/helpers/temp_dir.dart', ''), isEmpty);
      expect(
        violations('packages/typed_graphql_common/lib/a.dart', ''),
        isEmpty,
      );
    });

    test('control blocks nested deeper than 3 are rejected', () {
      const deep =
          'void main() {\n'
          '  for (;;) {\n'
          '    if (a) {\n'
          '      while (b) {\n'
          '        if (c) {}\n'
          '      }\n'
          '    }\n'
          '  }\n'
          '}\n';
      expect(violations(testPath, deep), [
        '$testPath:5: control blocks nest deeper than 3; return early or extract '
            'a method',
      ]);
    });

    test('methods in lib take at most 5 parameters, constructors any', () {
      expect(
        violations(
          libPath,
          classWith('  void f(int a, int b, int c, int d, int e, int f) {}\n'),
        ),
        [
          '$libPath:3: A.f takes 6 parameters, over 5; take a parameter object',
        ],
      );
      expect(
        violations(
          libPath,
          classWith('  A(int a, int b, int c, int d, int e, int f);\n'),
        ),
        isEmpty,
      );
    });

    test('a file in lib declares one public class or sealed family', () {
      expect(
        violations(
          libPath,
          '/// A.\nfinal class A {}\n\n/// B.\nfinal class B {}\n',
        ),
        [
          '$libPath:1: A, B are separate public types; keep one public class or '
              'sealed family per file',
        ],
      );
      expect(
        violations(
          libPath,
          'sealed class R {}\n\nfinal class S(int v)\n    extends R;\n\n'
          'final class F extends R {}\n\nfinal class _Helper {}\n',
        ),
        isEmpty,
      );
    });

    test('paths with Windows separators are read', () {
      expect(
        violations(r'packages\p\lib\src\utils.dart', "part 'b.dart';\n"),
        [
          'packages/p/lib/src/utils.dart:1: a part directive; split into '
              'libraries',
          'packages/p/lib/src/utils.dart:1: a utils or helpers file; name it '
              'after what it does',
        ],
      );
    });
  });

  group('size measurements', () {
    String lines(int count) => List.filled(count, '// line\n').join();

    test('a file in lib may have 300 lines, a test 500', () {
      expect(rules.oversizedFile(libPath, lines(300)), isNull);
      expect(rules.oversizedFile(libPath, lines(301)), 301);
      expect(rules.oversizedFile(testPath, lines(500)), isNull);
      expect(
        rules.oversizedFile(r'packages\p\test\a_test.dart', lines(501)),
        501,
      );
    });

    test('a method in lib may have 40 lines', () {
      String method(int bodyLines) =>
          classWith('  void run() {\n${'    f();\n' * bodyLines}  }\n');
      expect(rules.longMethods(libPath, method(38)), isEmpty);
      expect(rules.longMethods(libPath, method(39)), {'$libPath#A.run': 41});
      expect(rules.longMethods(testPath, method(39)), isEmpty);
    });

    test('an arrow body counts, a long field initializer does not', () {
      expect(
        rules.longMethods(
          libPath,
          classWith('  List<int> get all => [\n${'    1,\n' * 45}  ];\n'),
        ),
        {'$libPath#A.all': 47},
      );
      expect(
        rules.longMethods(
          libPath,
          classWith('  static const all = [\n${'    1,\n' * 45}  ];\n'),
        ),
        isEmpty,
      );
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `dart test test/quality/code_rules_fixtures_test.dart`
Expected: FAIL, because `code_rules.dart` does not exist.

- [ ] **Step 3: Implement `CodeRules`**

Create `test/quality/code_rules.dart`:

```dart
import 'blanked_code.dart';
import 'declaration_scanner.dart';
import 'nesting_meter.dart';

/// The code rules of `CLAUDE.md` ("Code rules") that a test can check,
/// applied to one Dart file of the workspace.
///
/// [violations] are the rules that allow no exception. [oversizedFile]
/// and [longMethods] are measurements: the size ratchet compares them with
/// an allowlist. Paths may use `\` (Windows) or `/`.
final class CodeRules {
  /// Creates the rules.
  const CodeRules();

  /// The most lines a file in `lib/` (or `bin/`) may have.
  static const int libFileLimit = 300;

  /// The most lines a file in `test/` (or `tool/`) may have.
  static const int testFileLimit = 500;

  /// The most lines a method, getter, operator or constructor in `lib/`
  /// may have, signature and closing bracket included.
  static const int methodLimit = 40;

  /// The most parameters a method in `lib/` may take; constructors are
  /// exempt.
  static const int parameterLimit = 5;

  /// The most control blocks that may nest.
  static const int nestingLimit = 3;

  static final RegExp _part = RegExp(r'^part\b');
  static final RegExp _dynamic = RegExp(r'\bdynamic\b');
  static final RegExp _catch = RegExp(r'\bcatch\s*\(');
  static final RegExp _catchWithOn = RegExp(
    r'\bon\s+[\w$<>?,. ]+\s+catch\s*\(',
  );
  static final RegExp _grabBag = RegExp(
    r'(?:^|_)(?:utils?|helpers?|common|misc)(?:_|\.dart$|$)',
  );
  static final RegExp _sealedRoot = RegExp(r'\bsealed\s+(?:class|mixin)\b');

  /// The violations of the rules that allow no exception, each as
  /// `path:line: what is wrong`.
  List<String> violations(String path, String content) {
    final file = _File(path, content);
    return [
      ..._lineRules(file),
      ..._nesting(file),
      for (final function in file.scanner.functions)
        if (function.name != 'main')
          '${file.path}:${function.lineNumber}: the top-level function '
              '${function.name}; put it in a class',
      if (file.isLib) ..._libRules(file),
    ];
  }

  /// The number of lines of the file at [path], as `wc -l` counts them,
  /// when it is over its limit; null when it is within it.
  int? oversizedFile(String path, String content) {
    final file = _File(path, content);
    final lines = '\n'.allMatches(content).length;
    return lines > (file.isLib ? libFileLimit : testFileLimit) ? lines : null;
  }

  /// The methods of a file in `lib/` over [methodLimit], keyed by
  /// `path#Type.member`, with their number of lines.
  Map<String, int> longMethods(String path, String content) {
    final file = _File(path, content);
    if (!file.isLib) {
      return const {};
    }
    return {
      for (final member in file.scanner.members)
        if (member.isCallable && member.length > methodLimit)
          '${file.path}#${member.name}': member.length,
    };
  }

  List<String> _lineRules(_File file) => [
    for (var i = 0; i < file.code.lines.length; i++)
      ...switch (file.code.lines[i]) {
        final line when _part.hasMatch(line) => [
          '${file.path}:${i + 1}: a part directive; split into libraries',
        ],
        final line when _dynamic.hasMatch(line) => [
          '${file.path}:${i + 1}: dynamic; use Object? or a real type',
        ],
        final line when _catch.hasMatch(line) && !_catchWithOn.hasMatch(line) =>
          ['${file.path}:${i + 1}: a catch without on; name the exception'],
        _ => const <String>[],
      },
  ];

  List<String> _nesting(_File file) => [
    for (final line in NestingMeter(file.code).linesDeeperThan(nestingLimit))
      '${file.path}:${line + 1}: control blocks nest deeper than '
          '$nestingLimit; return early or extract a method',
  ];

  List<String> _libRules(_File file) => [
    if (file.pathInPackage.any(_grabBag.hasMatch))
      '${file.path}:1: a utils or helpers file; name it after what it does',
    for (final member in file.scanner.members)
      if (member.isCallable &&
          !member.isConstructor &&
          member.parameterCount > parameterLimit)
        '${file.path}:${member.lineNumber}: ${member.name} takes '
            '${member.parameterCount} parameters, over $parameterLimit; '
            'take a parameter object',
    ?_publicTypes(file),
  ];

  /// The violation of "one public class or sealed family per file", or
  /// null when the file keeps it.
  String? _publicTypes(_File file) {
    final public = [
      for (final type in file.scanner.types)
        if (!type.type.name.startsWith('_')) type,
    ];
    final roots = [
      for (final type in public)
        if (_sealedRoot.hasMatch(type.header)) type.type.name,
    ];
    final families = [
      for (final type in public)
        if (!roots.any(
          (root) => RegExp(
            '\\b(?:extends|implements|with)\\b[^{;]*\\b$root\\b',
          ).hasMatch(type.header),
        ))
          type.type.name,
    ];
    return families.length <= 1
        ? null
        : '${file.path}:1: ${families.join(', ')} are separate public types; '
              'keep one public class or sealed family per file';
  }
}

/// One file being checked: its path with `/` separators and its code.
final class _File(String path, final String content) {
  final String path = path.replaceAll(r'\', '/');

  // `late`: the size rules count lines without blanking, and only some
  // rules need the declarations.
  late final BlankedCode code = BlankedCode(content);
  late final DeclarationScanner scanner = DeclarationScanner(code);

  static const Set<String> _sourceFolders = {'lib', 'bin', 'test', 'tool'};

  /// The folders and the file name from the source folder (`lib`, `bin`,
  /// `test` or `tool`) down, the source folder first.
  List<String> get pathInPackage => path
      .split('/')
      .skipWhile((folder) => !_sourceFolders.contains(folder))
      .toList();

  /// Whether the file is library code (`lib/` or `bin/`) rather than a
  /// test or a tool.
  bool get isLib => switch (pathInPackage) {
    ['test' || 'tool', ...] => false,
    _ => true,
  };
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `dart test test/quality/code_rules_fixtures_test.dart`
Expected: `+13: All tests passed!`

- [ ] **Step 5: Write the ratchet over the workspace**

Create `test/quality/workspace_files.dart`:

```dart
import 'dart:io';

/// The Dart files the code rules check: `lib/`, `bin/`, `test/` and
/// `tool/` of every package in `packages/`, and the workspace's own
/// `test/`.
final class WorkspaceFiles(
  /// The workspace root, the folder of the root `pubspec.yaml`.
  final String root,
) {
  /// Creates a reader of the workspace at [root].
  this;

  /// The content of every file, keyed by its path from [root] with `/`
  /// separators, in path order.
  Map<String, String> read() {
    final folders = [
      for (final package in _packages())
        for (final folder in const ['lib', 'bin', 'test', 'tool'])
          Directory('${package.path}/$folder'),
      Directory('$root/test'),
    ];
    final files = {
      for (final folder in folders)
        if (folder.existsSync())
          for (final file in folder.listSync(recursive: true).whereType<File>())
            if (file.path.endsWith('.dart'))
              _relative(file.path): file.readAsStringSync(),
    };
    return Map.fromEntries(
      files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  List<Directory> _packages() =>
      Directory('$root/packages').listSync().whereType<Directory>().toList();

  String _relative(String path) =>
      path.substring(root.length + 1).replaceAll(r'\', '/');
}
```

Create `test/quality/code_rules_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'code_rules.dart';
import 'workspace_files.dart';

/// The size ratchet and the pattern rules of `CLAUDE.md` ("Code rules")
/// over the whole workspace. Run `dart test` from the workspace root.
void main() {
  const rules = CodeRules();

  /// Files over their size limit for good: catalogs with no logic.
  const permanent = {
    'packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart',
  };

  /// Files over their size limit when they were listed, with their lines
  /// then; such a file may only shrink. Empty: keep it so.
  const fileAllowlist = <String, int>{};

  /// Methods over the limit when they were listed (`path#Type.member`),
  /// with their lines then. Empty: keep it so.
  const methodAllowlist = <String, int>{};

  final files = WorkspaceFiles(Directory.current.path).read();

  test('runs from the workspace root', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('workspace:'));
    expect(files.keys, contains('test/quality/code_rules_test.dart'));
  });

  test('no file breaks a rule that allows no exception', () {
    final failures = [
      for (final MapEntry(key: path, value: content) in files.entries)
        ...rules.violations(path, content),
    ];
    if (failures.isNotEmpty) fail(failures.join('\n'));
  });

  test('no file is over its size limit, unless allowlisted and not grown', () {
    final failures = [
      for (final MapEntry(key: path, value: content) in files.entries)
        if (rules.oversizedFile(path, content) case final lines?)
          if (!permanent.contains(path) && lines > (fileAllowlist[path] ?? 0))
            '$path has $lines lines, over its limit; split it by '
                'responsibility, do not add it to the allowlist',
    ];
    if (failures.isNotEmpty) fail(failures.join('\n'));
  });

  test('no method is over 40 lines, unless allowlisted and not grown', () {
    final failures = [
      for (final MapEntry(key: path, value: content) in files.entries)
        for (final MapEntry(key: method, value: lines)
            in rules.longMethods(path, content).entries)
          if (lines > (methodAllowlist[method] ?? 0))
            '$method has $lines lines, over ${CodeRules.methodLimit}; split '
                'it into named steps, do not add it to the allowlist',
    ];
    if (failures.isNotEmpty) fail(failures.join('\n'));
  });
}
```

- [ ] **Step 6: Check that the ratchet bites**

Add a violation, run the suite, then remove the file:

```sh
printf 'void helper(dynamic x) {}\n' > packages/typed_graphql_client/lib/bad.dart
dart test test/quality/code_rules_test.dart
rm packages/typed_graphql_client/lib/bad.dart
```

Expected: FAIL. The output names `packages/typed_graphql_client/lib/bad.dart:1:` twice: once for `dynamic` and once for the top-level function. After the `rm`, `git status --short` shows no change under `packages/`.

- [ ] **Step 7: Run the green check**

Expected: the root `dart test` ends with `+34: All tests passed!`, and every package with `+2`.

- [ ] **Step 8: Commit**

```bash
git add test/quality
git commit -q -m "test(quality): enforce the code rules with a workspace ratchet"
```

### Task 5: Core layer rule

**Files:**
- Create: `packages/typed_graphql/test/quality/layer_rule.dart`
- Test: `packages/typed_graphql/test/quality/layers_test.dart`

**Interfaces:**
- Consumes: the core package from Task 1. `lib/src/` does not exist yet; the test tolerates that.
- Produces:
  - `final class LayerRule` with `const LayerRule()`;
  - `static const List<String> layers = ['diagnostics', 'language', 'protocol', 'schema', 'validation']`;
  - `List<String> check(String filePath, String content)`.

  A library under `lib/src/<layer>/` may import:
  - its own layer and lower layers;
  - `dart:async`, `dart:collection`, `dart:convert`, `dart:core`, `dart:math` and `dart:typed_data`;
  - `package:meta/`.

  Anything else is a violation. Tasks 6 to 11 must keep `layers_test.dart` green.

- [ ] **Step 1: Write the failing test**

Create `packages/typed_graphql/test/quality/layers_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'layer_rule.dart';

void main() {
  const rule = LayerRule();

  group('LayerRule', () {
    test('allows the same layer, lower layers and pure Dart', () {
      expect(
        rule.check(
          'lib/src/protocol/graphql_error.dart',
          "import 'dart:convert';\n"
              "import 'package:meta/meta.dart';\n"
              "import '../diagnostics/source_location.dart';\n"
              "import 'json_value.dart';\n",
        ),
        isEmpty,
      );
    });

    test('rejects an import of a higher layer', () {
      expect(
        rule.check(
          'lib/src/diagnostics/diagnostic.dart',
          "import '../protocol/json_value.dart';\n",
        ),
        [
          'diagnostics/diagnostic.dart imports ../protocol/json_value.dart: '
              'diagnostics must not depend on protocol',
        ],
      );
    });

    test('rejects an export of a higher layer', () {
      expect(
        rule.check(
          'lib/src/language/ast.dart',
          'export "../schema/schema.dart";\n',
        ),
        hasLength(1),
      );
    });

    test('rejects dart:io and packages other than meta', () {
      expect(
        rule.check(
          'lib/src/protocol/a.dart',
          "import 'dart:io';\nimport 'package:collection/collection.dart';\n",
        ),
        hasLength(2),
      );
    });

    test('rejects the barrel and folders that are not layers', () {
      expect(
        rule.check(
          'lib/src/protocol/a.dart',
          "import '../../typed_graphql.dart';\n",
        ),
        hasLength(1),
      );
      expect(rule.check('lib/src/misc/a.dart', ''), hasLength(1));
      expect(rule.check('lib/src/a.dart', ''), hasLength(1));
    });

    test('reads Windows paths', () {
      expect(
        rule.check(
          r'C:\work\packages\typed_graphql\lib\src\diagnostics\a.dart',
          "import '../schema/schema.dart';\n",
        ),
        [
          'diagnostics/a.dart imports ../schema/schema.dart: '
              'diagnostics must not depend on schema',
        ],
      );
    });
  });

  test('lib/src follows the layer rule', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      startsWith('name: typed_graphql\n'),
      reason: 'run from packages/typed_graphql',
    );
    final src = Directory('lib/src');
    final files = src.existsSync()
        ? src.listSync(recursive: true).whereType<File>()
        : const <File>[];
    final violations = [
      for (final file in files)
        if (file.path.endsWith('.dart'))
          ...rule.check(file.path, file.readAsStringSync()),
    ];
    expect(violations, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `(cd packages/typed_graphql && dart test test/quality/layers_test.dart)`
Expected: FAIL, because `layer_rule.dart` does not exist.

- [ ] **Step 3: Implement `LayerRule`**

Create `packages/typed_graphql/test/quality/layer_rule.dart`:

```dart
/// The core's import rules (spec §1, R0.6), checked on the text of one
/// library under `lib/src/`.
///
/// Every library lives in a layer folder. A layer imports only its own
/// folder and the layers listed before it; the core imports no platform
/// library outside pure Dart and no package other than `meta`.
final class LayerRule {
  /// Creates the rule.
  const LayerRule();

  /// The layer folders under `lib/src/`, lowest first. A folder that does
  /// not exist yet is simply not scanned.
  static const List<String> layers = [
    'diagnostics',
    'language',
    'protocol',
    'schema',
    'validation',
  ];

  /// The platform libraries that run on the VM, AOT, dart2js and dart2wasm.
  static const Set<String> _pureDart = {
    'dart:async',
    'dart:collection',
    'dart:convert',
    'dart:core',
    'dart:math',
    'dart:typed_data',
  };

  static final RegExp _directive = RegExp(
    r'''^(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  /// The violations in [content], the text of the library at [filePath].
  ///
  /// [filePath] contains `lib/src/` and may use `\` (Windows) or `/`.
  List<String> check(String filePath, String content) {
    final path = _pathInSrc(filePath);
    final layer = _layerOf(path);
    if (layer == null) {
      return ['$path is not in a layer folder: ${layers.join(', ')}'];
    }
    return [
      for (final match in _directive.allMatches(content))
        ?_violation(path, layer, match.group(1)!),
    ];
  }

  /// What is wrong with [path], in [layer], importing [target]; null when
  /// nothing is.
  String? _violation(String path, int layer, String target) {
    if (target.startsWith('dart:')) {
      return _pureDart.contains(target)
          ? null
          : '$path imports $target: the core is pure Dart (R0.6)';
    }
    if (target.startsWith('package:')) {
      return target.startsWith('package:meta/')
          ? null
          : '$path imports $target: the core depends only on meta';
    }
    final resolved = Uri.parse(path).resolve(target).path;
    final targetLayer = _layerOf(resolved);
    if (targetLayer == null) {
      return '$path imports $target, which is not in a layer folder';
    }
    return targetLayer > layer
        ? '$path imports $target: ${layers[layer]} must not depend on '
              '${layers[targetLayer]}'
        : null;
  }

  /// [filePath] from the folder after `lib/src/`, with `/` separators.
  String _pathInSrc(String filePath) {
    final path = filePath.replaceAll(r'\', '/');
    const marker = 'lib/src/';
    final start = path.indexOf(marker);
    if (start < 0) {
      throw ArgumentError.value(filePath, 'filePath', 'is not in lib/src');
    }
    return path.substring(start + marker.length);
  }

  /// The index in [layers] of the folder [path] starts with; null when it
  /// starts with no layer folder.
  int? _layerOf(String path) {
    final slash = path.indexOf('/');
    if (slash < 0) {
      return null;
    }
    final index = layers.indexOf(path.substring(0, slash));
    return index < 0 ? null : index;
  }
}
```

- [ ] **Step 4: Run the green check**

Expected:
- `packages/typed_graphql` ends with `+9: All tests passed!`;
- the other packages end with `+2`;
- the root ends with `+34`.

- [ ] **Step 5: Commit**

```bash
git add packages/typed_graphql/test/quality
git commit -q -m "test(typed_graphql): enforce the core layer order"
```

### Task 6: Source, SourceLocation, SourceSpan

**Files:**
- Create: `packages/typed_graphql/lib/src/diagnostics/source_location.dart`, `source.dart`, `source_span.dart`
- Modify: `packages/typed_graphql/lib/typed_graphql.dart` (replace it whole), `packages/typed_graphql/CHANGELOG.md` (replace it whole)
- Test: `packages/typed_graphql/test/diagnostics/source_test.dart`

**Interfaces:**
- Consumes (Task 5): `layers_test.dart` must stay green. `diagnostics/` is the lowest layer and imports only `package:meta` and its own folder.
- Produces:
  - `final class const SourceLocation(final int line, final int column)`: both 1-based (asserted), with `==`, `hashCode`, and `toString()` giving `'line:column'`.
  - `final class Source(final String body, {final String name = 'GraphQL request'})`, with `SourceLocation locationOf(int offset)`. The column counts UTF-16 code units. An offset outside `0..body.length` throws a `RangeError`.
  - `final class const SourceSpan(final Source source, final int start, final int end)` (`@immutable`), with:
    - `SourceLocation get location`;
    - `String get text`;
    - `==` (same `Source` object, same offsets);
    - `toString()` giving `'name:line:column'`.

- [ ] **Step 1: Write the failing test**

Create `packages/typed_graphql/test/diagnostics/source_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('SourceLocation', () {
    test('compares by line and column', () {
      expect(const SourceLocation(2, 3), const SourceLocation(2, 3));
      expect(const SourceLocation(2, 3), isNot(const SourceLocation(3, 2)));
      expect(
        const SourceLocation(2, 3).hashCode,
        const SourceLocation(2, 3).hashCode,
      );
    });

    test('prints line:column', () {
      expect(const SourceLocation(2, 3).toString(), '2:3');
    });
  });

  group('Source.locationOf', () {
    test('counts lines and columns from 1', () {
      final source = Source('ab\ncd');
      expect(source.locationOf(0), const SourceLocation(1, 1));
      expect(source.locationOf(1), const SourceLocation(1, 2));
      expect(source.locationOf(3), const SourceLocation(2, 1));
      expect(source.locationOf(4), const SourceLocation(2, 2));
    });

    test('places the line feed on the line it ends', () {
      expect(Source('ab\ncd').locationOf(2), const SourceLocation(1, 3));
    });

    test('accepts the end of the document', () {
      expect(Source('ab\n').locationOf(3), const SourceLocation(2, 1));
      expect(Source('').locationOf(0), const SourceLocation(1, 1));
    });

    test(r'treats \r\n as one line terminator', () {
      final source = Source('a\r\nb');
      expect(source.locationOf(3), const SourceLocation(2, 1));
      expect(source.locationOf(1), const SourceLocation(1, 2));
      expect(source.locationOf(2), const SourceLocation(1, 3));
    });

    test(r'treats a lone \r as a line terminator', () {
      final source = Source('a\rb\r\rc');
      expect(source.locationOf(2), const SourceLocation(2, 1));
      expect(source.locationOf(4), const SourceLocation(3, 1));
      expect(source.locationOf(5), const SourceLocation(4, 1));
    });

    test(r'counts \n\r as two line terminators', () {
      expect(Source('a\n\rb').locationOf(3), const SourceLocation(3, 1));
    });

    test('does not treat U+2028 and U+2029 as line terminators', () {
      expect(
        Source('a b c').locationOf(4),
        const SourceLocation(1, 5),
      );
    });

    test('counts a byte order mark as one column', () {
      expect(Source('﻿query').locationOf(1), const SourceLocation(1, 2));
    });

    test('counts columns in UTF-16 code units', () {
      // U+1F600 is two code units, so `x` after it is column 3.
      expect(Source('\u{1F600}x').locationOf(2), const SourceLocation(1, 3));
    });

    test('finds the line in a long document', () {
      final source = Source(List.filled(1000, 'line').join('\n'));
      expect(source.locationOf(999 * 5 + 2), const SourceLocation(1000, 3));
      expect(source.locationOf(500 * 5), const SourceLocation(501, 1));
    });

    test('rejects an offset outside the document', () {
      final source = Source('ab');
      expect(() => source.locationOf(-1), throwsRangeError);
      expect(() => source.locationOf(3), throwsRangeError);
    });

    test('names a document from the wire like graphql-js', () {
      expect(Source('{ a }').name, 'GraphQL request');
      expect(Source('{ a }', name: 'lib/a.graphql').name, 'lib/a.graphql');
    });
  });

  group('SourceSpan', () {
    final source = Source('query {\n  hero\n}', name: 'hero.graphql');

    test('gives the location of its start and its text', () {
      final span = SourceSpan(source, 10, 14);
      expect(span.location, const SourceLocation(2, 3));
      expect(span.text, 'hero');
    });

    test('may be empty, at the end of the document', () {
      final end = source.body.length;
      expect(SourceSpan(source, end, end).text, '');
      expect(SourceSpan(source, end, end).location, const SourceLocation(3, 2));
    });

    test('prints name:line:column', () {
      expect(SourceSpan(source, 10, 14).toString(), 'hero.graphql:2:3');
    });

    test('is equal only for the same source and offsets', () {
      final same = Source(source.body, name: source.name);
      expect(SourceSpan(source, 10, 14), SourceSpan(source, 10, 14));
      expect(
        SourceSpan(source, 10, 14).hashCode,
        SourceSpan(source, 10, 14).hashCode,
      );
      expect(SourceSpan(source, 10, 14), isNot(SourceSpan(same, 10, 14)));
      expect(SourceSpan(source, 10, 14), isNot(SourceSpan(source, 10, 13)));
    });

    test('throws a RangeError when it runs past the document', () {
      final span = SourceSpan(source, 0, source.body.length + 1);
      expect(() => span.text, throwsRangeError);
      expect(
        () => SourceSpan(source, 99, 99).location,
        throwsRangeError,
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `(cd packages/typed_graphql && dart test test/diagnostics/source_test.dart)`
Expected: FAIL with compile errors, because `Source`, `SourceLocation` and `SourceSpan` are not defined.

- [ ] **Step 3: Implement**

Create `packages/typed_graphql/lib/src/diagnostics/source_location.dart`:

```dart
import 'package:meta/meta.dart';

/// A position in a GraphQL document as people count it: a 1-based [line]
/// and a 1-based [column] in UTF-16 code units.
///
/// It is also the shape of an entry of a GraphQL error's `locations`
/// (spec §7.1.2, "Error Result Format").
@immutable
final class const SourceLocation(
  /// The line, from 1.
  final int line,

  /// The column, from 1, counted in UTF-16 code units.
  final int column,
) {
  /// Creates a location; [line] and [column] are 1 or more.
  this
    : assert(line >= 1, 'line is 1-based'),
      assert(column >= 1, 'column is 1-based');

  @override
  bool operator ==(Object other) =>
      other is SourceLocation && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => '$line:$column';
}
```

Create `packages/typed_graphql/lib/src/diagnostics/source.dart`:

```dart
import 'source_location.dart';

/// The text of a GraphQL document and the name diagnostics show for it.
///
/// Offsets into [body] count UTF-16 code units, as `String.codeUnitAt`
/// does. [locationOf] turns an offset into a line and a column; the table of
/// line starts it needs is built on the first call, so a document that
/// reports no location is scanned only by the lexer.
final class Source(
  /// The document text.
  final String body, {

  /// The name diagnostics show: a file path, or `GraphQL request` (the
  /// name graphql-js uses) for a document that came over the wire.
  final String name = 'GraphQL request',
}) {
  /// Creates a source for [body].
  this;

  static const int _lineFeed = 0x0A;
  static const int _carriageReturn = 0x0D;

  // `late`: built on the first [locationOf] call and never before; most
  // documents never need a line or a column (spec §2).
  late final List<int> _lineStarts = _scanLineStarts();

  /// The line and column of [offset], both 1-based, the column in UTF-16
  /// code units.
  ///
  /// A line ends with `\r\n`, `\n` or a lone `\r` (spec §2.1.3,
  /// "LineTerminator"), as graphql-js `getLocation` counts them. [offset]
  /// may equal the length of [body], the end of the document; outside
  /// `0..body.length` it is a [RangeError].
  SourceLocation locationOf(int offset) {
    RangeError.checkValueInInterval(offset, 0, body.length, 'offset');
    final line = _lineIndexOf(offset);
    return SourceLocation(line + 1, offset - _lineStarts[line] + 1);
  }

  /// The index in [_lineStarts] of the last line that starts at or before
  /// [offset]: a binary search, since the starts ascend.
  int _lineIndexOf(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_lineStarts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// The offset where each line starts: 0, then the offset after every line
  /// terminator. A `\r` directly before a `\n` is part of that terminator.
  List<int> _scanLineStarts() {
    final starts = [0];
    for (var i = 0; i < body.length; i++) {
      final unit = body.codeUnitAt(i);
      if (unit == _carriageReturn && _isLineFeedAt(i + 1)) {
        continue;
      }
      if (unit == _lineFeed || unit == _carriageReturn) {
        starts.add(i + 1);
      }
    }
    return List.unmodifiable(starts);
  }

  /// Whether the code unit at [offset] exists and is `\n`.
  bool _isLineFeedAt(int offset) =>
      offset < body.length && body.codeUnitAt(offset) == _lineFeed;
}
```

Create `packages/typed_graphql/lib/src/diagnostics/source_span.dart`:

```dart
import 'package:meta/meta.dart';

import 'source.dart';
import 'source_location.dart';

/// A range of a [Source]: from [start] up to, not including, [end], both
/// offsets in UTF-16 code units. A diagnostic points at one.
@immutable
final class const SourceSpan(
  /// The source the offsets index.
  final Source source,

  /// The offset of the first code unit of the range.
  final int start,

  /// The offset after the last code unit; equal to [start] for an empty
  /// range, such as the end of the document.
  final int end,
) {
  /// Creates a span; `0 <= start <= end <= source.body.length`, and
  /// [location] and [text] throw a [RangeError] past the end.
  this
    : assert(start >= 0, 'start is not negative'),
      assert(start <= end, 'start is not after end');

  /// The line and column of [start].
  SourceLocation get location => source.locationOf(start);

  /// The text the span covers.
  String get text => source.body.substring(start, end);

  @override
  bool operator ==(Object other) =>
      other is SourceSpan &&
      identical(other.source, source) &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(identityHashCode(source), start, end);

  /// `name:line:column` of [start], the form editors and terminals link.
  @override
  String toString() => '${source.name}:$location';
}
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model.
library;

export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
```

Replace `packages/typed_graphql/CHANGELOG.md` with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `Source`, `SourceLocation` and `SourceSpan`: a document, 1-based lines
  and columns computed on demand, and ranges.
```

- [ ] **Step 4: Run it to verify it passes**

Run: `(cd packages/typed_graphql && dart test test/diagnostics/source_test.dart)`
Expected: `+19: All tests passed!`

- [ ] **Step 5: Run the green check**

Expected:
- `packages/typed_graphql` ends with `+28: All tests passed!`;
- the root ends with `+34`;
- the other packages end with `+2`.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_graphql
git commit -q -m "feat(typed_graphql): add Source, SourceLocation and SourceSpan"
```

### Task 7: DiagnosticSeverity, DiagnosticCode, Diagnostic, DiagnosticSink

**Files:**
- Create: `packages/typed_graphql/lib/src/diagnostics/diagnostic_severity.dart`, `diagnostic_code.dart`, `diagnostic.dart`, `diagnostic_sink.dart`
- Modify: `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql/CHANGELOG.md` (replace both whole)
- Test: `packages/typed_graphql/test/diagnostics/diagnostic_test.dart`, `packages/typed_graphql/test/diagnostics/diagnostic_sink_test.dart`

**Interfaces:**
- Consumes (Task 6): `Source`, `SourceSpan` (`.location`), `SourceLocation`.
- Produces:
  - `enum DiagnosticSeverity { error, warning }`.
  - `enum DiagnosticCode(final String id)`, with the single value `diagnosticLimitReached('GQL000')`. Its doc comment carries the range table (`GQL0xx` lexer and syntax … `GQL5xx` code generation). Later stages add values here, sorted by id, each with a doc comment.
  - `final class Diagnostic(final DiagnosticCode code, final DiagnosticSeverity severity, final String message, {final SourceSpan? span, List<SourceSpan> related = const []})`, with:
    - `related` (an unmodifiable copy);
    - `bool get isError`;
    - `List<SourceLocation> get locations`: the span's location, then the related spans';
    - `toString()` giving `'name:line:column: error GQL000: message'`.
  - `final class DiagnosticSink({int maxErrors = defaultMaxErrors})`, with:
    - `static const int defaultMaxErrors = 100`;
    - `bool get isFull`, `bool get hasErrors`;
    - `List<Diagnostic> get diagnostics` (an unmodifiable copy);
    - `void report(Diagnostic diagnostic)`.

    A `maxErrors` below 1 is an `ArgumentError`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/diagnostics/diagnostic_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('DiagnosticCode', () {
    test('every id is GQL and three digits', () {
      for (final code in DiagnosticCode.values) {
        expect(code.id, matches(RegExp(r'^GQL[0-5]\d\d$')), reason: code.name);
      }
    });

    test('ids are unique and sorted', () {
      final ids = [for (final code in DiagnosticCode.values) code.id];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, [...ids]..sort());
    });

    test('keeps the ids already published', () {
      expect(DiagnosticCode.diagnosticLimitReached.id, 'GQL000');
    });
  });

  group('Diagnostic', () {
    final source = Source('{\n  a\n  b\n}', name: 'q.graphql');

    test('prints the place, the severity, the id and the message', () {
      final diagnostic = Diagnostic(
        .diagnosticLimitReached,
        .error,
        'Too many errors.',
        span: SourceSpan(source, 4, 5),
      );
      expect(
        diagnostic.toString(),
        'q.graphql:2:3: error GQL000: Too many errors.',
      );
    });

    test('prints without a place when it has no span', () {
      final diagnostic = Diagnostic(.diagnosticLimitReached, .warning, 'Hm.');
      expect(diagnostic.toString(), 'warning GQL000: Hm.');
    });

    test('isError follows the severity', () {
      expect(Diagnostic(.diagnosticLimitReached, .error, 'x').isError, isTrue);
      expect(
        Diagnostic(.diagnosticLimitReached, .warning, 'x').isError,
        isFalse,
      );
    });

    test('lists the location of the span, then of the related spans', () {
      final diagnostic = Diagnostic(
        .diagnosticLimitReached,
        .error,
        'Fields conflict.',
        span: SourceSpan(source, 4, 5),
        related: [SourceSpan(source, 8, 9)],
      );
      expect(diagnostic.locations, const [
        SourceLocation(2, 3),
        SourceLocation(3, 3),
      ]);
    });

    test('has no locations without spans', () {
      expect(Diagnostic(.diagnosticLimitReached, .error, 'x').locations, []);
    });

    test('copies the related spans', () {
      final related = [SourceSpan(source, 8, 9)];
      final diagnostic = Diagnostic(
        .diagnosticLimitReached,
        .error,
        'x',
        related: related,
      );
      related.clear();
      expect(diagnostic.related, hasLength(1));
      expect(
        () => diagnostic.related.add(SourceSpan(source, 0, 1)),
        throwsUnsupportedError,
      );
    });
  });
}
```

Create `packages/typed_graphql/test/diagnostics/diagnostic_sink_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('{ a b c d }');

  Diagnostic error(int offset) => Diagnostic(
    .diagnosticLimitReached,
    .error,
    'error at $offset',
    span: SourceSpan(source, offset, offset + 1),
  );

  Diagnostic warning(int offset) => Diagnostic(
    .diagnosticLimitReached,
    .warning,
    'warning at $offset',
    span: SourceSpan(source, offset, offset + 1),
  );

  test('starts empty', () {
    final sink = DiagnosticSink();
    expect(sink.diagnostics, isEmpty);
    expect(sink.hasErrors, isFalse);
    expect(sink.isFull, isFalse);
    expect(sink.maxErrors, DiagnosticSink.defaultMaxErrors);
  });

  test('keeps diagnostics in the order they were reported', () {
    final sink = DiagnosticSink()
      ..report(error(6))
      ..report(warning(2))
      ..report(error(4));
    expect(
      [for (final d in sink.diagnostics) d.message],
      [
        'error at 6',
        'warning at 2',
        'error at 4',
      ],
    );
  });

  test('hasErrors ignores warnings', () {
    final sink = DiagnosticSink()..report(warning(2));
    expect(sink.hasErrors, isFalse);
    sink.report(error(4));
    expect(sink.hasErrors, isTrue);
  });

  test('replaces the first error over the limit with GQL000 and stops', () {
    final sink = DiagnosticSink(maxErrors: 2)
      ..report(error(2))
      ..report(error(4))
      ..report(error(6))
      ..report(error(8))
      ..report(warning(8));
    expect(sink.isFull, isTrue);
    expect(sink.diagnostics, hasLength(3));
    final limit = sink.diagnostics.last;
    expect(limit.code, DiagnosticCode.diagnosticLimitReached);
    expect(limit.severity, DiagnosticSeverity.error);
    expect(limit.span, SourceSpan(source, 6, 7));
    expect(limit.message, contains('limit of 2'));
  });

  test('does not count warnings toward the limit', () {
    final sink = DiagnosticSink(maxErrors: 1)
      ..report(warning(2))
      ..report(warning(4))
      ..report(error(6))
      ..report(warning(8));
    expect(sink.isFull, isFalse);
    expect(sink.diagnostics, hasLength(4));
  });

  test('gives a copy that cannot be modified', () {
    final sink = DiagnosticSink()..report(error(2));
    final seen = sink.diagnostics;
    sink.report(error(4));
    expect(seen, hasLength(1));
    expect(() => seen.add(error(6)), throwsUnsupportedError);
  });

  test('rejects a limit below 1', () {
    expect(() => DiagnosticSink(maxErrors: 0), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `(cd packages/typed_graphql && dart test test/diagnostics)`
Expected: FAIL with compile errors in the two new files, because `Diagnostic`, `DiagnosticCode`, `DiagnosticSeverity` and `DiagnosticSink` are not defined. `source_test.dart` still passes.

- [ ] **Step 3: Implement**

Create `packages/typed_graphql/lib/src/diagnostics/diagnostic_severity.dart`:

```dart
/// How serious a diagnostic is.
enum DiagnosticSeverity {
  /// The input is invalid: a result that carries one is a failure.
  error,

  /// The input is valid but suspicious, such as a use of a deprecated
  /// field; a success may carry warnings.
  warning,
}
```

Create `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`:

```dart
/// The catalog of diagnostic codes: one value per problem, each with a
/// stable [id] and a doc comment that says when it is reported.
///
/// An id is `GQL` and three digits; the hundreds digit is the area:
///
/// | Ids | Area | Codes added by |
/// |---|---|---|
/// | `GQL0xx` | lexer and syntax | M2 |
/// | `GQL1xx` | type system: building and validating a schema | M3 |
/// | `GQL2xx` | operation validation (the doc comment names the spec rule) | M4 |
/// | `GQL3xx` | coercion and execution | M5 |
/// | `GQL4xx` | transports and protocols | M6, M7 |
/// | `GQL5xx` | code generation | M8, M10 |
///
/// `GQL000` belongs to no area: any sink reports it when its limit is
/// reached. Values are sorted by [id]. An id is public API: it is never
/// renumbered, reused or removed. Stages add codes in minor versions, so do
/// not switch over this enum exhaustively: match the codes you handle and
/// add a wildcard case.
enum DiagnosticCode(
  /// The stable id, such as `GQL000`, shown in messages and documentation.
  final String id,
) {
  /// `GQL000`: a sink kept as many errors as its limit allows and dropped
  /// the rest. It is reported once, at the place of the first dropped
  /// error; the run behind the sink should stop.
  diagnosticLimitReached('GQL000');
}
```

Create `packages/typed_graphql/lib/src/diagnostics/diagnostic.dart`:

```dart
import 'diagnostic_code.dart';
import 'diagnostic_severity.dart';
import 'source_location.dart';
import 'source_span.dart';

/// One problem found in a document, a schema or a payload; immutable.
final class Diagnostic(
  /// The stable code; its [DiagnosticCode.id] appears in messages.
  final DiagnosticCode code,

  /// Whether this is an error or a warning.
  final DiagnosticSeverity severity,

  /// A sentence for people: what is wrong, in the terms of the input.
  final String message, {

  /// Where the problem is; null when it has no place in a source, such as
  /// a problem of a schema built in code.
  final SourceSpan? span,
  List<SourceSpan> related = const [],
}) {
  /// Creates a diagnostic.
  this;

  /// Other places that explain the problem, such as the first definition
  /// of a duplicated name, in the order the GraphQL error's `locations`
  /// list them after [span].
  final List<SourceSpan> related = List.unmodifiable(related);

  /// Whether [severity] is [DiagnosticSeverity.error].
  bool get isError => severity == .error;

  /// The line and column of [span] and then of each [related] span: the
  /// `locations` of the GraphQL error this diagnostic becomes.
  List<SourceLocation> get locations => [
    ?span?.location,
    for (final place in related) place.location,
  ];

  /// `name:line:column: severity GQLnnn: message`, without the place when
  /// there is no [span]: the form a terminal links to the source.
  @override
  String toString() {
    final place = span == null ? '' : '$span: ';
    return '$place${severity.name} ${code.id}: $message';
  }
}
```

Create `packages/typed_graphql/lib/src/diagnostics/diagnostic_sink.dart`:

```dart
import 'diagnostic.dart';
import 'diagnostic_code.dart';

/// Collects the diagnostics of one parse, validation or decoding run, in
/// the order they are reported.
///
/// The lexer, the parser and the validation rules take a sink through
/// their constructor and report into it; the public API turns
/// [diagnostics] into a result (spec §2). The order is never changed:
/// graphql-js reports in the same order, and the ported suites compare
/// lists.
///
/// A sink keeps at most [maxErrors] errors; warnings do not count. The
/// next error adds one [DiagnosticCode.diagnosticLimitReached] error at its
/// place instead, [isFull] becomes true and every later report is ignored,
/// as graphql-js's `maxErrors` aborts validation.
final class DiagnosticSink {
  /// Creates an empty sink that keeps at most [maxErrors] errors.
  DiagnosticSink({this.maxErrors = defaultMaxErrors}) {
    if (maxErrors < 1) {
      throw ArgumentError.value(maxErrors, 'maxErrors', 'must be at least 1');
    }
  }

  /// The default of [maxErrors]: graphql-js's `maxErrors` for validation.
  static const int defaultMaxErrors = 100;

  /// The most errors this sink keeps before it reports the limit.
  final int maxErrors;

  final List<Diagnostic> _diagnostics = [];
  int _errorCount = 0;
  bool _isFull = false;

  /// Whether the limit was reached: later reports are ignored, so the run
  /// may stop.
  bool get isFull => _isFull;

  /// Whether an error was reported.
  bool get hasErrors => _errorCount > 0;

  /// The diagnostics in the order they were reported, the limit error last
  /// when [isFull]; a copy that cannot be modified.
  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Adds [diagnostic], unless the sink is full.
  void report(Diagnostic diagnostic) {
    if (_isFull) {
      return;
    }
    if (diagnostic.isError && _errorCount == maxErrors) {
      _isFull = true;
      _diagnostics.add(_limitReached(diagnostic));
      return;
    }
    if (diagnostic.isError) {
      _errorCount++;
    }
    _diagnostics.add(diagnostic);
  }

  /// The error that stands for [dropped] and every error after it.
  Diagnostic _limitReached(Diagnostic dropped) => Diagnostic(
    .diagnosticLimitReached,
    .error,
    'Too many errors: the limit of $maxErrors was reached and the rest are '
    'not reported.',
    span: dropped.span,
  );
}
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
```

Replace `packages/typed_graphql/CHANGELOG.md` with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `Source`, `SourceLocation` and `SourceSpan`: a document, 1-based lines
  and columns computed on demand, and ranges.
- `DiagnosticCode` (the catalog, seeded with `GQL000`), `DiagnosticSeverity`,
  `Diagnostic` and `DiagnosticSink`.
```

- [ ] **Step 4: Run them to verify they pass**

Run: `(cd packages/typed_graphql && dart test test/diagnostics)`
Expected: `+35: All tests passed!` (19 + 9 + 7).

- [ ] **Step 5: Run the green check**

Expected:
- `packages/typed_graphql` ends with `+44: All tests passed!`;
- the root ends with `+34`;
- the other packages end with `+2`.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_graphql
git commit -q -m "feat(typed_graphql): add the diagnostics model"
```

### Task 8: PathSegment, DecodeResult, JsonValue

**Files:**
- Create: `packages/typed_graphql/lib/src/protocol/path_segment.dart`, `decode_result.dart`, `json_value.dart`
- Modify: `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql/CHANGELOG.md` (replace both whole)
- Test: `packages/typed_graphql/test/protocol/decode_result_test.dart`, `packages/typed_graphql/test/protocol/json_value_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks besides the layer rule. `protocol/` may import `diagnostics/`.
- Produces:
  - `sealed class const PathSegment()`, with two subclasses:
    - `final class const PathKey(final String name)`;
    - `final class const PathIndex(final int index)`: the index is asserted `>= 0`.

    Both have value equality, and `toString()` gives the bare name or index.
  - `sealed class const DecodeResult<T>()`, with `DecodeResult<T> inside(PathSegment segment)` and two subclasses:
    - `final class const DecodeSuccess<T>(final T value)`;
    - `final class const DecodeFailure(final String message, {final List<PathSegment> path = const []}) extends DecodeResult<Never>`, whose `toString()` gives the JSONPath, for example `$.errors[0].message: expected a string`.
  - `sealed class const JsonValue()`, with `Object? toJson()` and `toString()` giving compact JSON. Its subclasses:
    - `JsonNull()`;
    - `JsonBool(bool value)`;
    - `JsonNumber(num value)`: an `ArgumentError` when the value is not finite; `static const int maxSafeInteger`; `int? get asInt`;
    - `JsonString(String value)`;
    - `JsonArray(List<JsonValue> items)`;
    - `JsonObject(Map<String, JsonValue> fields)`, with `JsonValue? operator [](String key)`.

    Arrays and objects hold unmodifiable copies.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/protocol/decode_result_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('PathSegment', () {
    test('compares keys by name and indexes by index', () {
      expect(const PathKey('a'), const PathKey('a'));
      expect(const PathIndex(0), const PathIndex(0));
      expect(const PathKey('0'), isNot(const PathIndex(0)));
      expect(const PathKey('a').hashCode, const PathKey('a').hashCode);
    });

    test('prints the bare key or index', () {
      expect(const PathKey('hero').toString(), 'hero');
      expect(const PathIndex(2).toString(), '2');
    });
  });

  group('DecodeResult', () {
    test('a switch over it is exhaustive', () {
      String describe(DecodeResult<int> result) => switch (result) {
        DecodeSuccess(:final value) => 'value $value',
        DecodeFailure(:final message) => 'failure $message',
      };
      expect(describe(const DecodeSuccess(1)), 'value 1');
      expect(describe(const DecodeFailure('bad')), 'failure bad');
    });

    test('inside leaves a success as it is', () {
      const result = DecodeSuccess(1);
      expect(result.inside(const PathKey('a')), same(result));
    });

    test('inside puts the step in front of the failure path', () {
      final failure = const DecodeFailure('expected a string')
          .inside(const PathKey('message'))
          .inside(const PathIndex(0))
          .inside(const PathKey('errors'));
      expect(
        failure,
        const DecodeFailure(
          'expected a string',
          path: [PathKey('errors'), PathIndex(0), PathKey('message')],
        ),
      );
    });

    test('a failure prints its path as JSONPath', () {
      const failure = DecodeFailure(
        'expected a string',
        path: [PathKey('errors'), PathIndex(0), PathKey('message')],
      );
      expect(failure.toString(), r'$.errors[0].message: expected a string');
      expect(const DecodeFailure('bad').toString(), r'$: bad');
    });

    test('failures compare by message and path, not by printed form', () {
      const dotted = DecodeFailure('bad', path: [PathKey('a.b')]);
      const nested = DecodeFailure('bad', path: [PathKey('a'), PathKey('b')]);
      expect(dotted.toString(), nested.toString());
      expect(dotted, isNot(nested));
      expect(
        const DecodeFailure('bad', path: [PathIndex(1)]).hashCode,
        const DecodeFailure('bad', path: [PathIndex(1)]).hashCode,
      );
    });

    test('successes compare by value', () {
      expect(const DecodeSuccess('a'), const DecodeSuccess('a'));
      expect(const DecodeSuccess('a'), isNot(const DecodeSuccess('b')));
    });
  });
}
```

Create `packages/typed_graphql/test/protocol/json_value_test.dart`:

```dart
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  test('a switch over JsonValue is exhaustive', () {
    String kind(JsonValue value) => switch (value) {
      JsonNull() => 'null',
      JsonBool() => 'bool',
      JsonNumber() => 'number',
      JsonString() => 'string',
      JsonArray() => 'array',
      JsonObject() => 'object',
    };
    expect(kind(const JsonNull()), 'null');
    expect(kind(JsonObject(const {})), 'object');
  });

  group('JsonNumber', () {
    test('1 and 1.0 are equal, as on the web', () {
      expect(JsonNumber(1), JsonNumber(1.0));
      expect(JsonNumber(1).hashCode, JsonNumber(1.0).hashCode);
    });

    test('rejects NaN and the infinities', () {
      expect(() => JsonNumber(double.nan), throwsArgumentError);
      expect(() => JsonNumber(double.infinity), throwsArgumentError);
      expect(() => JsonNumber(double.negativeInfinity), throwsArgumentError);
    });

    test('asInt reads whole numbers up to 2^53 - 1', () {
      expect(JsonNumber(3).asInt, 3);
      expect(JsonNumber(3.0).asInt, 3);
      expect(JsonNumber(-3).asInt, -3);
      expect(JsonNumber(JsonNumber.maxSafeInteger).asInt, 9007199254740991);
      expect(JsonNumber(-JsonNumber.maxSafeInteger).asInt, -9007199254740991);
    });

    test('asInt is null for fractions and unsafe magnitudes', () {
      expect(JsonNumber(1.5).asInt, isNull);
      expect(JsonNumber(1e300).asInt, isNull);
      expect(JsonNumber(9007199254740992.0).asInt, isNull);
    });
  });

  group('equality', () {
    test('compares arrays item by item', () {
      expect(
        JsonArray([JsonNumber(1), const JsonString('a')]),
        JsonArray([JsonNumber(1.0), const JsonString('a')]),
      );
      expect(
        JsonArray([JsonNumber(1), JsonNumber(2)]),
        isNot(JsonArray([JsonNumber(2), JsonNumber(1)])),
      );
    });

    test('compares objects whatever the order of their keys', () {
      final ab = JsonObject({'a': JsonNumber(1), 'b': const JsonNull()});
      final ba = JsonObject({'b': const JsonNull(), 'a': JsonNumber(1)});
      expect(ab, ba);
      expect(ab.hashCode, ba.hashCode);
      expect(ab, isNot(JsonObject({'a': JsonNumber(1)})));
    });

    test('tells a JSON null from an absent key', () {
      final object = JsonObject({'a': const JsonNull()});
      expect(object['a'], const JsonNull());
      expect(object['b'], isNull);
      expect(object, isNot(JsonObject(const {})));
    });

    test('different kinds are never equal', () {
      expect(const JsonString('1'), isNot(JsonNumber(1)));
      expect(const JsonBool(false), isNot(const JsonNull()));
    });
  });

  group('immutability', () {
    test('copies the items and fields it is given', () {
      final items = <JsonValue>[JsonNumber(1)];
      final fields = <String, JsonValue>{'a': JsonNumber(1)};
      final array = JsonArray(items);
      final object = JsonObject(fields);
      items.clear();
      fields.clear();
      expect(array.items, hasLength(1));
      expect(object.fields, hasLength(1));
    });

    test('cannot be modified', () {
      expect(
        () => JsonArray(const []).items.add(const JsonNull()),
        throwsUnsupportedError,
      );
      expect(
        () => JsonObject(const {}).fields['a'] = const JsonNull(),
        throwsUnsupportedError,
      );
    });
  });

  group('toJson', () {
    test('gives plain Dart objects that jsonEncode writes', () {
      final value = JsonObject({
        'a': JsonArray([JsonNumber(1), const JsonBool(true), const JsonNull()]),
        'b': JsonObject({'c': const JsonString('d')}),
      });
      expect(value.toJson(), {
        'a': [1, true, null],
        'b': {'c': 'd'},
      });
      expect(jsonEncode(value.toJson()), '{"a":[1,true,null],"b":{"c":"d"}}');
    });

    test('toString is compact JSON', () {
      expect(
        JsonObject({
          'a': JsonArray([const JsonString('x')]),
        }).toString(),
        '{"a":["x"]}',
      );
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `(cd packages/typed_graphql && dart test test/protocol)`
Expected: FAIL with compile errors, because `PathKey`, `DecodeSuccess`, `JsonValue` and the rest are not defined.

- [ ] **Step 3: Implement**

Create `packages/typed_graphql/lib/src/protocol/path_segment.dart`:

```dart
import 'package:meta/meta.dart';

/// One step of a path into a JSON value: a key of an object or an index of
/// an array.
///
/// A GraphQL error's `path` (spec §7.1.2, "response path") is a list of
/// them: response names and list indexes from the root of `data`. A
/// [DecodeFailure] uses the same steps to say where the bad value is.
@immutable
sealed class const PathSegment() {
  /// Creates a step.
  this;
}

/// A key of an object; in a response path, a response name (the alias
/// when there is one).
final class const PathKey(
  /// The key.
  final String name,
) extends PathSegment {
  /// Creates a key step.
  this;

  @override
  bool operator ==(Object other) => other is PathKey && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// An index of an array, from 0.
final class const PathIndex(
  /// The index.
  final int index,
) extends PathSegment {
  /// Creates an index step; [index] is not negative.
  this : assert(index >= 0, 'index is not negative');

  @override
  bool operator ==(Object other) => other is PathIndex && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => '$index';
}
```

Create `packages/typed_graphql/lib/src/protocol/decode_result.dart`:

```dart
import 'package:meta/meta.dart';

import 'path_segment.dart';

/// The result of reading untrusted input: a value, or why there is none.
///
/// Decoding never throws on bad input (spec §0, principle 3): a caller
/// switches over [DecodeSuccess] and [DecodeFailure].
@immutable
sealed class const DecodeResult<T>() {
  /// Creates a result.
  this;

  /// This result with a failure placed inside [segment] of its parent; a
  /// success is returned as it is.
  DecodeResult<T> inside(PathSegment segment) => switch (this) {
    DecodeSuccess() => this,
    DecodeFailure(:final message, :final path) => DecodeFailure(
      message,
      path: List.unmodifiable([segment, ...path]),
    ),
  };
}

/// Decoding produced [value].
final class const DecodeSuccess<T>(
  /// The decoded value.
  final T value,
) extends DecodeResult<T> {
  /// Creates a success.
  this;

  @override
  bool operator ==(Object other) =>
      other is DecodeSuccess<Object?> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DecodeSuccess($value)';
}

/// Decoding failed: [message] says what is wrong, [path] where.
final class const DecodeFailure(
  /// What is wrong, such as `expected a string`.
  final String message, {

  /// The keys and indexes from the root of the input to the bad value;
  /// empty when the root itself is bad.
  final List<PathSegment> path = const [],
}) extends DecodeResult<Never> {
  /// Creates a failure.
  this;

  @override
  bool operator ==(Object other) =>
      other is DecodeFailure &&
      other.message == message &&
      _isSamePath(other.path);

  @override
  int get hashCode => Object.hash(message, Object.hashAll(path));

  /// The path as JSONPath and the message: `$.errors[0].message: expected
  /// a string`.
  @override
  String toString() {
    final where = StringBuffer(r'$');
    for (final segment in path) {
      where.write(switch (segment) {
        PathKey(:final name) => '.$name',
        PathIndex(:final index) => '[$index]',
      });
    }
    return '$where: $message';
  }

  /// Whether [other] has the steps of [path], in the same order.
  bool _isSamePath(List<PathSegment> other) {
    if (other.length != path.length) {
      return false;
    }
    for (var i = 0; i < path.length; i++) {
      if (other[i] != path[i]) {
        return false;
      }
    }
    return true;
  }
}
```

Create `packages/typed_graphql/lib/src/protocol/json_value.dart`:

```dart
import 'dart:convert';

/// A JSON value: the type of arbitrary JSON in the public API (R0.2).
///
/// A sealed family, so a `switch` over it is exhaustive. Values are
/// immutable and compare by value: arrays item by item, objects by keys
/// and values whatever their order. Every number is one [JsonNumber],
/// because the web cannot tell `1` from `1.0`. Untrusted input becomes a
/// [JsonValue] through `JsonReader`, never by a cast.
sealed class const JsonValue() {
  /// Creates a value.
  this;

  /// This value as plain Dart objects (`null`, `bool`, `num`, `String`,
  /// `List<Object?>`, `Map<String, Object?>`), which `jsonEncode` writes.
  Object? toJson();

  /// This value as compact JSON text.
  @override
  String toString() => jsonEncode(toJson());
}

/// The JSON `null`.
final class const JsonNull() extends JsonValue {
  /// Creates the JSON `null`.
  this;

  @override
  Null toJson() => null;

  @override
  bool operator ==(Object other) => other is JsonNull;

  @override
  int get hashCode => null.hashCode;
}

/// `true` or `false`.
final class const JsonBool(
  /// The boolean.
  final bool value,
) extends JsonValue {
  /// Creates a boolean.
  this;

  @override
  bool toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonBool && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A finite number.
///
/// `1` and `1.0` are equal, as they are on the web. [asInt] reads a whole
/// number the same way on every platform.
final class JsonNumber(
  /// The number; never NaN or infinite.
  final num value,
) extends JsonValue {
  /// Creates a number; NaN and the infinities are an [ArgumentError], JSON
  /// cannot write them.
  this {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'is not a finite number');
    }
  }

  /// The largest integer every platform holds exactly: 2^53 - 1.
  static const int maxSafeInteger = 9007199254740991;

  /// [value] as an `int` when it is a whole number no larger in magnitude
  /// than [maxSafeInteger]; otherwise null.
  ///
  /// The bound gives the same answer on every platform: past it the web
  /// has already rounded the number, the VM has not.
  int? get asInt {
    if (value % 1 != 0 || value.abs() > maxSafeInteger) {
      return null;
    }
    return value.toInt();
  }

  @override
  num toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A string.
final class const JsonString(
  /// The string.
  final String value,
) extends JsonValue {
  /// Creates a string.
  this;

  @override
  String toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonString && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// An array.
final class JsonArray(List<JsonValue> items) extends JsonValue {
  /// Creates an array of a copy of [items].
  this;

  /// The items, in order; the list cannot be modified.
  final List<JsonValue> items = List.unmodifiable(items);

  @override
  List<Object?> toJson() => [for (final item in items) item.toJson()];

  @override
  bool operator ==(Object other) {
    if (other is! JsonArray || other.items.length != items.length) {
      return false;
    }
    for (var i = 0; i < items.length; i++) {
      if (other.items[i] != items[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(items);
}

/// An object: string keys in their order of insertion, each with a value.
final class JsonObject(Map<String, JsonValue> fields) extends JsonValue {
  /// Creates an object of a copy of [fields].
  this;

  /// The keys and values, in order; the map cannot be modified.
  final Map<String, JsonValue> fields = Map.unmodifiable(fields);

  /// The value at [key], or null when the object has no such key (a JSON
  /// `null` is a [JsonNull]).
  JsonValue? operator [](String key) => fields[key];

  @override
  Map<String, Object?> toJson() => {
    for (final MapEntry(:key, :value) in fields.entries) key: value.toJson(),
  };

  @override
  bool operator ==(Object other) {
    if (other is! JsonObject || other.fields.length != fields.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in fields.entries) {
      if (other.fields[key] != value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final MapEntry(:key, :value) in fields.entries)
      Object.hash(key, value),
  ]);
}
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
```

Replace `packages/typed_graphql/CHANGELOG.md` with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `Source`, `SourceLocation` and `SourceSpan`: a document, 1-based lines
  and columns computed on demand, and ranges.
- `DiagnosticCode` (the catalog, seeded with `GQL000`), `DiagnosticSeverity`,
  `Diagnostic` and `DiagnosticSink`.
- `JsonValue`, a sealed family for arbitrary JSON; `PathSegment` and
  `DecodeResult`.
```

- [ ] **Step 4: Run them to verify they pass**

Run: `(cd packages/typed_graphql && dart test test/protocol)`
Expected: `+21: All tests passed!` (8 + 13).

- [ ] **Step 5: Run the green check**

Expected:
- `packages/typed_graphql` ends with `+65: All tests passed!`;
- the root ends with `+34`;
- the other packages end with `+2`.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_graphql
git commit -q -m "feat(typed_graphql): add JsonValue, PathSegment and DecodeResult"
```

### Task 9: JsonReader

**Files:**
- Create: `packages/typed_graphql/lib/src/protocol/json_reader.dart`
- Modify: `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql/CHANGELOG.md` (replace both whole)
- Test: `packages/typed_graphql/test/protocol/json_reader_test.dart`

**Interfaces:**
- Consumes (Task 8): the `JsonValue` family, `DecodeSuccess`, `DecodeFailure`, `.inside(PathSegment)`, `PathKey`, `PathIndex`.
- Produces: `final class JsonReader`, with:
  - `const JsonReader({this.maxDepth = defaultMaxDepth})` and `static const int defaultMaxDepth = 512`;
  - `DecodeResult<JsonValue> parse(String text)`;
  - `DecodeResult<JsonValue> read(Object? value)`, which reads the output of `jsonDecode`.

  The failure messages are:
  - `not JSON: …`;
  - `… is not a finite number`;
  - `the key … is not a string`;
  - `not a JSON value`;
  - `arrays and objects are nested deeper than <maxDepth>`.

- [ ] **Step 1: Write the failing test**

Create `packages/typed_graphql/test/protocol/json_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const reader = JsonReader();

  JsonValue parsed(String text) => switch (reader.parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  String nested(int depth) => '${'[' * depth}${']' * depth}';

  group('parse', () {
    test('reads every kind of value', () {
      expect(
        parsed('{"a": [1, 2.5, "s", true, null], "b": {}}'),
        JsonObject({
          'a': JsonArray([
            JsonNumber(1),
            JsonNumber(2.5),
            const JsonString('s'),
            const JsonBool(true),
            const JsonNull(),
          ]),
          'b': JsonObject(const {}),
        }),
      );
    });

    test('reads 1.0 as the whole number 1', () {
      final number = parsed('1.0') as JsonNumber;
      expect(number, JsonNumber(1));
      expect(number.asInt, 1);
    });

    test('reads integers past 2^53 - 1 without a safe int', () {
      final number = parsed('9007199254740993') as JsonNumber;
      expect(number.asInt, isNull);
      expect(
        (parsed('9007199254740991') as JsonNumber).asInt,
        9007199254740991,
      );
    });

    test('rejects a number too large to be finite', () {
      expect(reader.parse('1e400'), isA<DecodeFailure>());
      expect(
        reader.parse('{"a": [-1e400]}'),
        const DecodeFailure(
          '-Infinity is not a finite number',
          path: [PathKey('a'), PathIndex(0)],
        ),
      );
    });

    test('keeps the last value of a repeated key', () {
      expect(parsed('{"a": 1, "a": 2}'), JsonObject({'a': JsonNumber(2)}));
    });

    test('rejects text that is not JSON', () {
      for (final text in ['', '{', '{"a": 1,}', "{'a': 1}", 'NaN', '01']) {
        final result = reader.parse(text);
        expect(result, isA<DecodeFailure>(), reason: text);
        expect((result as DecodeFailure).message, startsWith('not JSON'));
      }
    });
  });

  group('depth', () {
    test('accepts nesting up to maxDepth', () {
      expect(reader.parse(nested(512)), isA<DecodeSuccess<JsonValue>>());
      expect(
        const JsonReader(maxDepth: 0).parse('"s"'),
        const DecodeSuccess<JsonValue>(JsonString('s')),
      );
    });

    test('rejects nesting past maxDepth before decoding', () {
      expect(
        reader.parse(nested(513)),
        const DecodeFailure('arrays and objects are nested deeper than 512'),
      );
      expect(reader.parse(nested(100000)), isA<DecodeFailure>());
      expect(
        const JsonReader(maxDepth: 1).parse('{"a": {}}'),
        isA<DecodeFailure>(),
      );
    });

    test('does not count brackets inside strings', () {
      const reader = JsonReader(maxDepth: 1);
      expect(
        reader.parse(r'["[[{{", "\"[[", "\\"]'),
        isA<DecodeSuccess<JsonValue>>(),
      );
    });

    test('read rejects nesting past maxDepth too', () {
      const reader = JsonReader(maxDepth: 2);
      expect(reader.read([[]]), isA<DecodeSuccess<JsonValue>>());
      expect(
        reader.read([
          [<Object?>[]],
        ]),
        isA<DecodeFailure>(),
      );
    });
  });

  group('read', () {
    test('converts plain Dart objects', () {
      expect(
        reader.read({
          'a': [1, 'b', null],
        }),
        DecodeSuccess<JsonValue>(
          JsonObject({
            'a': JsonArray([
              JsonNumber(1),
              const JsonString('b'),
              const JsonNull(),
            ]),
          }),
        ),
      );
    });

    test('rejects a key that is not a string', () {
      expect(
        reader.read({
          'a': {1: 'x'},
        }),
        const DecodeFailure('the key 1 is not a string', path: [PathKey('a')]),
      );
    });

    test('rejects objects that are not JSON, with their path', () {
      expect(
        reader.read([1, DateTime(2026)]),
        const DecodeFailure('not a JSON value', path: [PathIndex(1)]),
      );
      expect(
        reader.read({'a': double.nan}),
        const DecodeFailure('NaN is not a finite number', path: [PathKey('a')]),
      );
    });

    test('rejects a list that contains itself', () {
      final list = <Object?>[];
      list.add(list);
      expect(reader.read(list), isA<DecodeFailure>());
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `(cd packages/typed_graphql && dart test test/protocol/json_reader_test.dart)`
Expected: FAIL with compile errors, because `JsonReader` is not defined.

- [ ] **Step 3: Implement**

Create `packages/typed_graphql/lib/src/protocol/json_reader.dart`:

```dart
import 'dart:convert';

import 'decode_result.dart';
import 'json_value.dart';
import 'path_segment.dart';

/// Reads untrusted JSON, as text or as the output of `jsonDecode`, into a
/// [JsonValue].
///
/// Bad input is a [DecodeFailure], never an exception: text that is not
/// JSON, a number too large to be finite (`1e400`), a map key that is not a
/// string, a Dart object that is not JSON, and arrays and objects nested
/// deeper than [maxDepth]. A key repeated in one object keeps its last
/// value, as `jsonDecode` and JavaScript's `JSON.parse` do.
final class JsonReader {
  /// Creates a reader that accepts at most [maxDepth] arrays and objects
  /// nested in one another.
  const JsonReader({this.maxDepth = defaultMaxDepth});

  /// The default of [maxDepth].
  static const int defaultMaxDepth = 512;

  /// The most arrays and objects nested in one another; a scalar at the top
  /// has depth 0, `[]` has 1, `[[]]` has 2.
  final int maxDepth;

  /// Parses [text] as JSON.
  ///
  /// The nesting is measured on the text before `jsonDecode` runs, because
  /// `jsonDecode` on the web recurses once per level and would overflow
  /// the stack first.
  DecodeResult<JsonValue> parse(String text) {
    if (_NestingScanner(text).isDeeperThan(maxDepth)) {
      return _tooDeep();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      return DecodeFailure('not JSON: ${error.message}');
    }
    return read(decoded);
  }

  /// Converts [value]: the output of `jsonDecode`, or plain Dart objects
  /// (`null`, `bool`, `num`, `String`, `List`, `Map` with `String` keys).
  DecodeResult<JsonValue> read(Object? value) => _read(value, 0);

  DecodeResult<JsonValue> _read(Object? value, int depth) => switch (value) {
    null => const DecodeSuccess(JsonNull()),
    bool() => DecodeSuccess(JsonBool(value)),
    num() when value.isFinite => DecodeSuccess(JsonNumber(value)),
    num() => DecodeFailure('$value is not a finite number'),
    String() => DecodeSuccess(JsonString(value)),
    List<Object?>() => _array(value, depth + 1),
    Map<Object?, Object?>() => _object(value, depth + 1),
    _ => const DecodeFailure('not a JSON value'),
  };

  DecodeResult<JsonValue> _array(List<Object?> list, int depth) {
    if (depth > maxDepth) {
      return _tooDeep();
    }
    final items = <JsonValue>[];
    for (var i = 0; i < list.length; i++) {
      switch (_read(list[i], depth).inside(PathIndex(i))) {
        case DecodeSuccess(:final value):
          items.add(value);
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonArray(items));
  }

  DecodeResult<JsonValue> _object(Map<Object?, Object?> map, int depth) {
    if (depth > maxDepth) {
      return _tooDeep();
    }
    final fields = <String, JsonValue>{};
    for (final MapEntry(:key, :value) in map.entries) {
      if (key is! String) {
        return DecodeFailure('the key $key is not a string');
      }
      switch (_read(value, depth).inside(PathKey(key))) {
        case DecodeSuccess(:final value):
          fields[key] = value;
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonObject(fields));
  }

  DecodeFailure _tooDeep() =>
      DecodeFailure('arrays and objects are nested deeper than $maxDepth');
}

/// Measures how deeply arrays and objects nest in JSON text without
/// parsing it: brackets inside strings do not count.
final class _NestingScanner(final String text) {
  static const int _quote = 0x22;
  static const int _backslash = 0x5C;
  static const int _openBracket = 0x5B;
  static const int _closeBracket = 0x5D;
  static const int _openBrace = 0x7B;
  static const int _closeBrace = 0x7D;

  /// Whether some array or object in [text] is nested deeper than [limit].
  bool isDeeperThan(int limit) {
    var depth = 0;
    var inString = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (inString) {
        i += unit == _backslash ? 1 : 0;
        inString = unit != _quote;
        continue;
      }
      inString = unit == _quote;
      depth += _change(unit);
      if (depth > limit) {
        return true;
      }
    }
    return false;
  }

  /// How [unit] changes the depth outside a string.
  int _change(int unit) => switch (unit) {
    _openBracket || _openBrace => 1,
    _closeBracket || _closeBrace => -1,
    _ => 0,
  };
}
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
```

Replace `packages/typed_graphql/CHANGELOG.md` with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `Source`, `SourceLocation` and `SourceSpan`: a document, 1-based lines
  and columns computed on demand, and ranges.
- `DiagnosticCode` (the catalog, seeded with `GQL000`), `DiagnosticSeverity`,
  `Diagnostic` and `DiagnosticSink`.
- `JsonValue`, a sealed family for arbitrary JSON; `PathSegment` and
  `DecodeResult`.
- `JsonReader`: JSON text to `JsonValue`, with a nesting limit and no
  exceptions.
```

- [ ] **Step 4: Run it to verify it passes, on the VM and in Chrome**

Run: `(cd packages/typed_graphql && dart test test/protocol/json_reader_test.dart && dart test -p chrome --compiler dart2js test/protocol/json_reader_test.dart)`
Expected: `+14: All tests passed!` twice. The Chrome run proves that 100 000 nested arrays do not overflow the dart2js stack. If no Chrome is installed, skip the second command: CI runs it (Task 12).

- [ ] **Step 5: Run the green check**

Expected:
- `packages/typed_graphql` ends with `+79: All tests passed!`;
- the root ends with `+34`;
- the other packages end with `+2`.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_graphql
git commit -q -m "feat(typed_graphql): add JsonReader"
```

### Task 10: JsonFieldReader and GraphQLError

**Files:**
- Create: `packages/typed_graphql/lib/src/protocol/json_field_reader.dart` (internal, not exported), `packages/typed_graphql/lib/src/protocol/graphql_error.dart`
- Modify: `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql/CHANGELOG.md` (replace both whole)
- Test: `packages/typed_graphql/test/protocol/json_field_reader_test.dart`, `packages/typed_graphql/test/protocol/graphql_error_test.dart`

**Interfaces:**
- Consumes:
  - Task 6: `SourceLocation`.
  - Task 8: the `JsonValue` family, `DecodeResult`, `PathSegment`.
  - Task 9: `JsonReader` (tests only).
- Produces:
  - `final class JsonFieldReader(final JsonObject object)`, in `lib/src/protocol/json_field_reader.dart`. It is imported by path in the tests and in Task 11, never exported. Its methods:
    - `DecodeResult<String> string(String key)`: a missing key gives `is required` and a wrong type gives `expected a string`, both inside `PathKey(key)`;
    - `DecodeResult<String?> optionalString(String key)`;
    - `DecodeResult<JsonObject?> optionalObject(String key)`;
    - `DecodeResult<List<T>?> optionalList<T>(String key, DecodeResult<T> Function(JsonValue item) decode)`.

    Each `optional*` method reads an absent key or `null` as null.
  - `final class GraphQLError(final String message, {List<SourceLocation> locations = const [], List<PathSegment>? path, final JsonObject? extensions})`, with:
    - `static DecodeResult<GraphQLError> decode(JsonValue json)`;
    - `JsonObject toJson()`;
    - equality by `toJson()`;
    - `toString()` giving `'GraphQLError(<json>)'`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/protocol/json_field_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/protocol/json_field_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final fields = JsonFieldReader(
    JsonObject({
      's': const JsonString('x'),
      'n': JsonNumber(1),
      'null': const JsonNull(),
      'o': JsonObject(const {}),
      'list': JsonArray([JsonNumber(1), JsonNumber(2)]),
    }),
  );

  DecodeResult<int> whole(JsonValue item) => switch (item) {
    JsonNumber(asInt: final int value) => DecodeSuccess(value),
    _ => const DecodeFailure('expected an int'),
  };

  test('string requires a string', () {
    expect(fields.string('s'), const DecodeSuccess('x'));
    expect(
      fields.string('n'),
      const DecodeFailure('expected a string', path: [PathKey('n')]),
    );
    expect(
      fields.string('missing'),
      const DecodeFailure('is required', path: [PathKey('missing')]),
    );
    expect(fields.string('null'), isA<DecodeFailure>());
  });

  test('optionalString reads absent and null as null', () {
    expect(fields.optionalString('s'), const DecodeSuccess('x'));
    expect(
      fields.optionalString('missing'),
      const DecodeSuccess<String?>(null),
    );
    expect(fields.optionalString('null'), const DecodeSuccess<String?>(null));
    expect(fields.optionalString('n'), isA<DecodeFailure>());
  });

  test('optionalObject reads absent and null as null', () {
    expect(
      fields.optionalObject('o'),
      DecodeSuccess<JsonObject?>(JsonObject(const {})),
    );
    expect(
      fields.optionalObject('null'),
      const DecodeSuccess<JsonObject?>(null),
    );
    expect(
      fields.optionalObject('list'),
      const DecodeFailure('expected an object', path: [PathKey('list')]),
    );
  });

  test('optionalList reads every item', () {
    final result =
        fields.optionalList('list', whole) as DecodeSuccess<List<int>?>;
    expect(result.value, [1, 2]);
    expect(
      fields.optionalList('missing', whole),
      const DecodeSuccess<List<int>?>(null),
    );
  });

  test('optionalList places a bad item inside its index and key', () {
    final reader = JsonFieldReader(
      JsonObject({
        'list': JsonArray([JsonNumber(1), const JsonString('two')]),
      }),
    );
    expect(
      reader.optionalList('list', whole),
      const DecodeFailure(
        'expected an int',
        path: [PathKey('list'), PathIndex(1)],
      ),
    );
    expect(
      fields.optionalList('o', whole),
      const DecodeFailure('expected an array', path: [PathKey('o')]),
    );
  });
}
```

Create `packages/typed_graphql/test/protocol/graphql_error_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  DecodeResult<GraphQLError> decode(String text) =>
      GraphQLError.decode(json(text));

  final full = GraphQLError(
    'Name for character with ID 1002 could not be fetched.',
    locations: const [SourceLocation(6, 7)],
    path: const [
      PathKey('hero'),
      PathKey('heroFriends'),
      PathIndex(1),
      PathKey('name'),
    ],
    extensions: JsonObject({'code': const JsonString('CAN_NOT_FETCH_BY_ID')}),
  );

  group('toJson', () {
    test('writes the spec example, message first', () {
      expect(
        full.toJson().toString(),
        '{"message":"Name for character with ID 1002 could not be fetched.",'
        '"locations":[{"line":6,"column":7}],'
        '"path":["hero","heroFriends",1,"name"],'
        '"extensions":{"code":"CAN_NOT_FETCH_BY_ID"}}',
      );
    });

    test('leaves out empty locations and unset path and extensions', () {
      expect(GraphQLError('Boom').toJson().toString(), '{"message":"Boom"}');
    });

    test('writes an empty path when the path is empty', () {
      expect(
        GraphQLError('Boom', path: const []).toJson().toString(),
        '{"message":"Boom","path":[]}',
      );
    });
  });

  group('decode', () {
    test('reads what toJson writes', () {
      expect(GraphQLError.decode(full.toJson()), DecodeSuccess(full));
    });

    test('reads a path that mixes names and indexes', () {
      final error = decode('{"message": "m", "path": ["a", 0, "b", 12]}');
      expect(
        (error as DecodeSuccess<GraphQLError>).value.path,
        const [PathKey('a'), PathIndex(0), PathKey('b'), PathIndex(12)],
      );
    });

    test('reads 1.0 as the index 1, since the web cannot tell them apart', () {
      expect(
        decode('{"message": "m", "path": [1.0]}'),
        DecodeSuccess(GraphQLError('m', path: const [PathIndex(1)])),
      );
    });

    test('rejects an index that is negative or not whole', () {
      for (final index in ['-1', '1.5', '1e300', 'true', 'null']) {
        expect(
          decode('{"message": "m", "path": ["a", $index]}'),
          const DecodeFailure(
            'expected a string or an index from 0',
            path: [PathKey('path'), PathIndex(1)],
          ),
          reason: index,
        );
      }
    });

    test('rejects a location with a line or column below 1', () {
      for (final location in [
        '{"line": 0, "column": 1}',
        '{"line": 1, "column": 0}',
        '{"line": 1.5, "column": 1}',
        '{"line": 1}',
        '[1, 1]',
      ]) {
        final result = decode('{"message": "m", "locations": [$location]}');
        expect(
          (result as DecodeFailure).path,
          const [PathKey('locations'), PathIndex(0)],
          reason: location,
        );
      }
    });

    test('treats null and absent fields alike', () {
      expect(
        decode(
          '{"message": "m", "locations": null, "path": null, "extensions": null}',
        ),
        DecodeSuccess(GraphQLError('m')),
      );
    });

    test('reads empty locations as none', () {
      expect(
        decode('{"message": "m", "locations": []}'),
        DecodeSuccess(GraphQLError('m')),
      );
    });

    test('ignores keys the spec does not define', () {
      expect(
        decode('{"message": "m", "code": 42}'),
        DecodeSuccess(GraphQLError('m')),
      );
    });

    test('requires a string message', () {
      expect(
        decode('{"locations": []}'),
        const DecodeFailure('is required', path: [PathKey('message')]),
      );
      expect(
        decode('{"message": null}'),
        const DecodeFailure('expected a string', path: [PathKey('message')]),
      );
      expect(decode('"m"'), const DecodeFailure('expected an object'));
    });

    test('requires extensions to be an object', () {
      expect(
        decode('{"message": "m", "extensions": []}'),
        const DecodeFailure(
          'expected an object',
          path: [PathKey('extensions')],
        ),
      );
    });
  });

  group('equality', () {
    test('compares by JSON', () {
      expect(
        GraphQLError('m', path: const [PathIndex(0)]),
        GraphQLError('m', path: const [PathIndex(0)]),
      );
      expect(GraphQLError('m').hashCode, GraphQLError('m').hashCode);
      expect(GraphQLError('m'), isNot(GraphQLError('m', path: const [])));
    });

    test('copies its lists', () {
      final locations = [const SourceLocation(1, 1)];
      final error = GraphQLError('m', locations: locations);
      locations.clear();
      expect(error.locations, hasLength(1));
      expect(error.locations.clear, throwsUnsupportedError);
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `(cd packages/typed_graphql && dart test test/protocol/json_field_reader_test.dart test/protocol/graphql_error_test.dart)`
Expected: FAIL. `json_field_reader.dart` does not exist, and `GraphQLError` is not defined.

- [ ] **Step 3: Implement**

Create `packages/typed_graphql/lib/src/protocol/json_field_reader.dart`:

```dart
import 'decode_result.dart';
import 'json_value.dart';
import 'path_segment.dart';

/// Reads the fields of one [JsonObject] by key; a missing or mistyped
/// field is a [DecodeFailure] placed inside its key.
///
/// The optional readers treat an absent key and a JSON `null` alike, as
/// GraphQL's request and response formats do.
final class JsonFieldReader(
  /// The object whose fields are read.
  final JsonObject object,
) {
  /// Creates a reader of [object].
  this;

  /// The string at [key], which must be present.
  DecodeResult<String> string(String key) => switch (object[key]) {
    JsonString(:final value) => DecodeSuccess(value),
    null => const DecodeFailure('is required').inside(PathKey(key)),
    _ => const DecodeFailure('expected a string').inside(PathKey(key)),
  };

  /// The string at [key], or null when it is absent or `null`.
  DecodeResult<String?> optionalString(String key) => switch (object[key]) {
    null || JsonNull() => const DecodeSuccess(null),
    JsonString(:final value) => DecodeSuccess(value),
    _ => const DecodeFailure('expected a string').inside(PathKey(key)),
  };

  /// The object at [key], or null when it is absent or `null`.
  DecodeResult<JsonObject?> optionalObject(String key) => switch (object[key]) {
    null || JsonNull() => const DecodeSuccess(null),
    final JsonObject value => DecodeSuccess(value),
    _ => const DecodeFailure('expected an object').inside(PathKey(key)),
  };

  /// The array at [key] with every item read by [decode], or null when it
  /// is absent or `null`; the first bad item is the failure.
  DecodeResult<List<T>?> optionalList<T>(
    String key,
    DecodeResult<T> Function(JsonValue item) decode,
  ) => switch (object[key]) {
    null || JsonNull() => DecodeSuccess<List<T>?>(null),
    JsonArray(:final items) => _readAll(items, decode).inside(PathKey(key)),
    _ => const DecodeFailure('expected an array').inside(PathKey(key)),
  };

  /// Every item of [items] read by [decode], or the first failure.
  DecodeResult<List<T>> _readAll<T>(
    List<JsonValue> items,
    DecodeResult<T> Function(JsonValue item) decode,
  ) {
    final values = <T>[];
    for (var i = 0; i < items.length; i++) {
      switch (decode(items[i]).inside(PathIndex(i))) {
        case DecodeSuccess(:final value):
          values.add(value);
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(List.unmodifiable(values));
  }
}
```

Create `packages/typed_graphql/lib/src/protocol/graphql_error.dart`:

```dart
import '../diagnostics/source_location.dart';
import 'decode_result.dart';
import 'json_field_reader.dart';
import 'json_value.dart';
import 'path_segment.dart';

/// An error of a GraphQL response, in the format of spec §7.1.2 ("Errors").
///
/// Both sides use it: a server writes it with [toJson], a client reads it
/// with [decode]. Two errors are equal when their JSON is equal.
final class GraphQLError(
  /// What went wrong, for the developer reading it.
  final String message, {
  List<SourceLocation> locations = const [],
  List<PathSegment>? path,

  /// Extra data the server attached, such as an error code; null when the
  /// error has none.
  final JsonObject? extensions,
}) {
  /// Creates an error; the lists are copied.
  this;

  /// The places in the document the error is about; empty when it is
  /// about none.
  final List<SourceLocation> locations = List.unmodifiable(locations);

  /// The response path of the field the error is about: response names
  /// and list indexes from the root of `data`. Null when the error is not
  /// about a field.
  final List<PathSegment>? path = path == null ? null : List.unmodifiable(path);

  /// Reads an error from [json]; a missing or mistyped `message`,
  /// `locations`, `path` or `extensions` is a failure, other keys are
  /// ignored.
  static DecodeResult<GraphQLError> decode(JsonValue json) {
    if (json is! JsonObject) {
      return const DecodeFailure('expected an object');
    }
    final fields = JsonFieldReader(json);
    return switch ((
      fields.string('message'),
      fields.optionalList('locations', _location),
      fields.optionalList('path', _segment),
      fields.optionalObject('extensions'),
    )) {
      (
        DecodeSuccess(value: final message),
        DecodeSuccess(value: final locations),
        DecodeSuccess(value: final path),
        DecodeSuccess(value: final extensions),
      ) =>
        DecodeSuccess(
          GraphQLError(
            message,
            locations: locations ?? const [],
            path: path,
            extensions: extensions,
          ),
        ),
      (final DecodeFailure failure, _, _, _) ||
      (_, final DecodeFailure failure, _, _) ||
      (_, _, final DecodeFailure failure, _) ||
      (_, _, _, final DecodeFailure failure) => failure,
    };
  }

  /// This error as JSON: `message` first, then `locations` when there are
  /// any, `path` and `extensions` when they are set.
  JsonObject toJson() => JsonObject({
    'message': JsonString(message),
    if (locations.isNotEmpty)
      'locations': JsonArray([
        for (final SourceLocation(:line, :column) in locations)
          JsonObject({'line': JsonNumber(line), 'column': JsonNumber(column)}),
      ]),
    if (path case final path?)
      'path': JsonArray([
        for (final segment in path)
          switch (segment) {
            PathKey(:final name) => JsonString(name),
            PathIndex(:final index) => JsonNumber(index),
          },
      ]),
    'extensions': ?extensions,
  });

  @override
  bool operator ==(Object other) =>
      other is GraphQLError && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;

  @override
  String toString() => 'GraphQLError(${toJson()})';

  /// One entry of `locations`: `{"line": 1, "column": 2}`, both 1 or more.
  static DecodeResult<SourceLocation> _location(JsonValue json) =>
      switch (json) {
        JsonObject(
          fields: {
            'line': JsonNumber(asInt: final int line),
            'column': JsonNumber(asInt: final int column),
          },
        )
            when line >= 1 && column >= 1 =>
          DecodeSuccess(SourceLocation(line, column)),
        _ => const DecodeFailure(
          'expected {"line": n, "column": n} with whole numbers from 1',
        ),
      };

  /// One entry of `path`: a response name or a list index.
  static DecodeResult<PathSegment> _segment(JsonValue json) => switch (json) {
    JsonString(:final value) => DecodeSuccess(PathKey(value)),
    JsonNumber(asInt: final int index) when index >= 0 => DecodeSuccess(
      PathIndex(index),
    ),
    _ => const DecodeFailure('expected a string or an index from 0'),
  };
}
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
```

Replace `packages/typed_graphql/CHANGELOG.md` with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `Source`, `SourceLocation` and `SourceSpan`: a document, 1-based lines
  and columns computed on demand, and ranges.
- `DiagnosticCode` (the catalog, seeded with `GQL000`), `DiagnosticSeverity`,
  `Diagnostic` and `DiagnosticSink`.
- `JsonValue`, a sealed family for arbitrary JSON; `PathSegment` and
  `DecodeResult`.
- `JsonReader`: JSON text to `JsonValue`, with a nesting limit and no
  exceptions.
- `GraphQLError`: the error format of the spec, read and written.
```

- [ ] **Step 4: Run them to verify they pass**

Run: `(cd packages/typed_graphql && dart test test/protocol/json_field_reader_test.dart test/protocol/graphql_error_test.dart)`
Expected: `+20: All tests passed!` (5 + 15).

- [ ] **Step 5: Run the green check**

Expected:
- `packages/typed_graphql` ends with `+99: All tests passed!`;
- the root ends with `+34`;
- the other packages end with `+2`.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_graphql
git commit -q -m "feat(typed_graphql): add GraphQLError"
```

### Task 11: GraphQLRequest and ResponsePayload

**Files:**
- Create: `packages/typed_graphql/lib/src/protocol/graphql_request.dart`, `packages/typed_graphql/lib/src/protocol/response_payload.dart`
- Modify: `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql/CHANGELOG.md` (replace both whole)
- Test: `packages/typed_graphql/test/protocol/graphql_request_test.dart`, `packages/typed_graphql/test/protocol/response_payload_test.dart`

**Interfaces:**
- Consumes:
  - Task 8: the `JsonValue` family and `DecodeResult`.
  - Task 9: `JsonReader` (tests only).
  - Task 10: `JsonFieldReader` and `GraphQLError` (`.decode`, `.toJson()`).
- Produces:
  - `final class const GraphQLRequest({final String? query, final String? operationName, final JsonObject? variables, final JsonObject? extensions})`, with:
    - `static DecodeResult<GraphQLRequest> decode(JsonValue json)`;
    - `JsonObject toJson()`;
    - equality by JSON.
  - `sealed class ResponsePayload({List<GraphQLError> errors = const [], final JsonObject? extensions})`, with:
    - `static DecodeResult<ResponsePayload> decode(JsonValue json)`;
    - an abstract `JsonObject toJson()`;
    - two subclasses:
      - `final class ExecutionResult(final JsonObject? data, {super.errors, super.extensions})`;
      - `final class RequestErrorResult({required super.errors, super.extensions})`: empty `errors` is an `ArgumentError`.
  - A payload with a `data` key decodes as `ExecutionResult`; any other object decodes as `RequestErrorResult`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/protocol/graphql_request_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  DecodeResult<GraphQLRequest> decode(String text) =>
      GraphQLRequest.decode(json(text));

  test('writes only the fields that are set', () {
    final request = GraphQLRequest(
      query: r'query Hero($id: ID!) { hero(id: $id) { name } }',
      operationName: 'Hero',
      variables: JsonObject({'id': const JsonString('1')}),
    );
    expect(
      request.toJson().toString(),
      r'{"query":"query Hero($id: ID!) { hero(id: $id) { name } }",'
      '"operationName":"Hero","variables":{"id":"1"}}',
    );
    expect(const GraphQLRequest().toJson().toString(), '{}');
  });

  test('reads what toJson writes', () {
    final request = GraphQLRequest(
      query: '{ a }',
      operationName: 'A',
      variables: JsonObject({'x': JsonNumber(1)}),
      extensions: JsonObject({'k': const JsonBool(true)}),
    );
    expect(GraphQLRequest.decode(request.toJson()), DecodeSuccess(request));
  });

  test('reads a persisted query without a document', () {
    expect(
      decode(
        '{"extensions": {"persistedQuery": '
        '{"version": 1, "sha256Hash": "abc"}}}',
      ),
      DecodeSuccess(
        GraphQLRequest(
          extensions: JsonObject({
            'persistedQuery': JsonObject({
              'version': JsonNumber(1),
              'sha256Hash': const JsonString('abc'),
            }),
          }),
        ),
      ),
    );
  });

  test('treats null fields as absent', () {
    expect(
      decode(
        '{"query": "{ a }", "operationName": null, "variables": null, '
        '"extensions": null}',
      ),
      const DecodeSuccess(GraphQLRequest(query: '{ a }')),
    );
  });

  test('ignores keys it does not know, as GraphQL over HTTP requires', () {
    expect(
      decode('{"query": "{ a }", "id": 7}'),
      const DecodeSuccess(GraphQLRequest(query: '{ a }')),
    );
  });

  test('rejects mistyped fields with their path', () {
    expect(
      decode('{"query": 1}'),
      const DecodeFailure('expected a string', path: [PathKey('query')]),
    );
    expect(
      decode('{"variables": "x"}'),
      const DecodeFailure('expected an object', path: [PathKey('variables')]),
    );
    expect(decode('[]'), const DecodeFailure('expected an object'));
  });
}
```

Create `packages/typed_graphql/test/protocol/response_payload_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  DecodeResult<ResponsePayload> decode(String text) =>
      ResponsePayload.decode(json(text));

  final data = JsonObject({
    'hero': JsonObject({'name': const JsonString('R2-D2')}),
  });
  final error = GraphQLError('Boom', path: const [PathKey('hero')]);

  group('ExecutionResult', () {
    test('writes errors first, then data', () {
      expect(
        ExecutionResult(data, errors: [error]).toJson().toString(),
        '{"errors":[{"message":"Boom","path":["hero"]}],'
        '"data":{"hero":{"name":"R2-D2"}}}',
      );
    });

    test('leaves out empty errors and writes null data', () {
      expect(
        ExecutionResult(data).toJson().toString(),
        '{"data":{"hero":{"name":"R2-D2"}}}',
      );
      expect(
        ExecutionResult(null, errors: [error]).toJson().toString(),
        '{"errors":[{"message":"Boom","path":["hero"]}],"data":null}',
      );
    });

    test('is read when data is present, even null', () {
      expect(
        decode(
          '{"data": null, "errors": [{"message": "Boom", "path": ["hero"]}]}',
        ),
        DecodeSuccess<ResponsePayload>(ExecutionResult(null, errors: [error])),
      );
      expect(
        decode('{"data": {"hero": {"name": "R2-D2"}}}'),
        DecodeSuccess<ResponsePayload>(ExecutionResult(data)),
      );
    });

    test('reads what toJson writes', () {
      final result = ExecutionResult(
        data,
        errors: [error],
        extensions: JsonObject({'cost': JsonNumber(3)}),
      );
      expect(
        ResponsePayload.decode(result.toJson()),
        DecodeSuccess<ResponsePayload>(result),
      );
    });

    test('rejects data that is not an object', () {
      expect(
        decode('{"data": []}'),
        const DecodeFailure('expected an object', path: [PathKey('data')]),
      );
    });

    test('places a bad error at its index', () {
      expect(
        decode('{"data": null, "errors": [{"message": "a"}, {}]}'),
        const DecodeFailure(
          'is required',
          path: [PathKey('errors'), PathIndex(1), PathKey('message')],
        ),
      );
    });
  });

  group('RequestErrorResult', () {
    test('writes errors and no data', () {
      expect(
        RequestErrorResult(errors: [error]).toJson().toString(),
        '{"errors":[{"message":"Boom","path":["hero"]}]}',
      );
    });

    test('requires at least one error', () {
      expect(() => RequestErrorResult(errors: const []), throwsArgumentError);
    });

    test('is read when data is absent', () {
      expect(
        decode('{"errors": [{"message": "Boom", "path": ["hero"]}]}'),
        DecodeSuccess<ResponsePayload>(RequestErrorResult(errors: [error])),
      );
    });

    test('rejects a payload with neither data nor errors', () {
      for (final text in ['{}', '{"errors": []}', '{"errors": null}']) {
        expect(decode(text), isA<DecodeFailure>(), reason: text);
      }
    });

    test('reports a bad error before a missing data', () {
      expect(
        decode('{"errors": [{"message": 1}]}'),
        const DecodeFailure(
          'expected a string',
          path: [PathKey('errors'), PathIndex(0), PathKey('message')],
        ),
      );
    });
  });

  test('a switch over ResponsePayload is exhaustive', () {
    String kind(ResponsePayload payload) => switch (payload) {
      ExecutionResult() => 'execution',
      RequestErrorResult() => 'request error',
    };
    expect(kind(ExecutionResult(null)), 'execution');
  });

  test('rejects a payload that is not an object', () {
    expect(decode('[]'), const DecodeFailure('expected an object'));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `(cd packages/typed_graphql && dart test test/protocol/graphql_request_test.dart test/protocol/response_payload_test.dart)`
Expected: FAIL with compile errors, because `GraphQLRequest`, `ResponsePayload`, `ExecutionResult` and `RequestErrorResult` are not defined.

- [ ] **Step 3: Implement**

Create `packages/typed_graphql/lib/src/protocol/graphql_request.dart`:

```dart
import 'decode_result.dart';
import 'json_field_reader.dart';
import 'json_value.dart';

/// A GraphQL request as it travels over a transport: the body of a GraphQL
/// over HTTP POST, the payload of a graphql-ws `subscribe` message.
///
/// Every field may be absent: an automatic persisted query sends only a
/// hash in [extensions], and the server decides what a request needs.
/// Two requests are equal when their JSON is equal.
final class const GraphQLRequest({
  /// The document text.
  final String? query,

  /// The operation to run when the document has several.
  final String? operationName,

  /// The values of the operation's variables.
  final JsonObject? variables,

  /// Extra data for the server, such as a persisted query hash.
  final JsonObject? extensions,
}) {
  /// Creates a request.
  this;

  /// Reads a request from [json]; a mistyped `query`, `operationName`,
  /// `variables` or `extensions` is a failure, other keys are ignored as
  /// GraphQL over HTTP requires.
  static DecodeResult<GraphQLRequest> decode(JsonValue json) {
    if (json is! JsonObject) {
      return const DecodeFailure('expected an object');
    }
    final fields = JsonFieldReader(json);
    return switch ((
      fields.optionalString('query'),
      fields.optionalString('operationName'),
      fields.optionalObject('variables'),
      fields.optionalObject('extensions'),
    )) {
      (
        DecodeSuccess(value: final query),
        DecodeSuccess(value: final operationName),
        DecodeSuccess(value: final variables),
        DecodeSuccess(value: final extensions),
      ) =>
        DecodeSuccess(
          GraphQLRequest(
            query: query,
            operationName: operationName,
            variables: variables,
            extensions: extensions,
          ),
        ),
      (final DecodeFailure failure, _, _, _) ||
      (_, final DecodeFailure failure, _, _) ||
      (_, _, final DecodeFailure failure, _) ||
      (_, _, _, final DecodeFailure failure) => failure,
    };
  }

  /// This request as JSON, with the fields that are set.
  JsonObject toJson() => JsonObject({
    if (query case final query?) 'query': JsonString(query),
    if (operationName case final name?) 'operationName': JsonString(name),
    'variables': ?variables,
    'extensions': ?extensions,
  });

  @override
  bool operator ==(Object other) =>
      other is GraphQLRequest && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;

  @override
  String toString() => 'GraphQLRequest(${toJson()})';
}
```

Create `packages/typed_graphql/lib/src/protocol/response_payload.dart`:

```dart
import 'decode_result.dart';
import 'graphql_error.dart';
import 'json_field_reader.dart';
import 'json_value.dart';

/// The body of a GraphQL response (spec §7.1, "Response Format"): an
/// [ExecutionResult] when the operation ran, a [RequestErrorResult] when
/// it did not.
///
/// It is the payload on the wire. The client's `GraphQLResponse` is a
/// different, typed thing built from it.
sealed class ResponsePayload({
  List<GraphQLError> errors = const [],

  /// Extra data for the client, such as tracing; null when there is none.
  final JsonObject? extensions,
}) {
  /// Creates a payload; [errors] is copied.
  this;

  /// The errors, in the order they were raised.
  final List<GraphQLError> errors = List.unmodifiable(errors);

  /// Reads a payload from [json]: with a `data` key it is an
  /// [ExecutionResult], without one a [RequestErrorResult].
  static DecodeResult<ResponsePayload> decode(JsonValue json) => switch (json) {
    JsonObject(:final fields) when fields.containsKey('data') =>
      ExecutionResult._decode(JsonFieldReader(json)),
    JsonObject() => RequestErrorResult._decode(JsonFieldReader(json)),
    _ => const DecodeFailure('expected an object'),
  };

  /// This payload as JSON: `errors` first, as spec §7.1 suggests.
  JsonObject toJson();

  /// [errors] as a JSON array.
  JsonArray get _errorsJson =>
      JsonArray([for (final error in errors) error.toJson()]);
}

/// The result of running an operation: [data], and the [errors] raised on
/// the way (partial data when both are there).
final class ExecutionResult(
  /// The data; null when an error left none (`"data": null`).
  final JsonObject? data, {
  super.errors,
  super.extensions,
}) extends ResponsePayload {
  /// Creates an execution result.
  this;

  @override
  JsonObject toJson() => JsonObject({
    if (errors.isNotEmpty) 'errors': _errorsJson,
    'data': data ?? const JsonNull(),
    'extensions': ?extensions,
  });

  @override
  bool operator ==(Object other) =>
      other is ExecutionResult && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;

  @override
  String toString() => 'ExecutionResult(${toJson()})';

  static DecodeResult<ResponsePayload> _decode(JsonFieldReader fields) =>
      switch ((
        fields.optionalObject('data'),
        fields.optionalList('errors', GraphQLError.decode),
        fields.optionalObject('extensions'),
      )) {
        (
          DecodeSuccess(value: final data),
          DecodeSuccess(value: final errors),
          DecodeSuccess(value: final extensions),
        ) =>
          DecodeSuccess(
            ExecutionResult(
              data,
              errors: errors ?? const [],
              extensions: extensions,
            ),
          ),
        (final DecodeFailure failure, _, _) ||
        (_, final DecodeFailure failure, _) ||
        (_, _, final DecodeFailure failure) => failure,
      };
}

/// A request that failed before the operation ran, such as a syntax or
/// validation error: no `data`, at least one error.
final class RequestErrorResult({required super.errors, super.extensions})
    extends ResponsePayload {
  /// Creates a request error result; an empty [errors] is an
  /// [ArgumentError].
  this {
    if (errors.isEmpty) {
      throw ArgumentError.value(errors, 'errors', 'is empty');
    }
  }

  @override
  JsonObject toJson() =>
      JsonObject({'errors': _errorsJson, 'extensions': ?extensions});

  @override
  bool operator ==(Object other) =>
      other is RequestErrorResult && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;

  @override
  String toString() => 'RequestErrorResult(${toJson()})';

  static DecodeResult<ResponsePayload> _decode(JsonFieldReader fields) =>
      switch ((
        fields.optionalList('errors', GraphQLError.decode),
        fields.optionalObject('extensions'),
      )) {
        (
          DecodeSuccess(value: final errors?),
          DecodeSuccess(value: final extensions),
        )
            when errors.isNotEmpty =>
          DecodeSuccess(
            RequestErrorResult(errors: errors, extensions: extensions),
          ),
        (final DecodeFailure failure, _) ||
        (_, final DecodeFailure failure) => failure,
        _ => const DecodeFailure(
          'expected "data", or a non-empty "errors" when "data" is absent',
        ),
      };
}
```

Replace `packages/typed_graphql/lib/typed_graphql.dart` with:

```dart
/// GraphQL for Dart: the language, the type system, validation and the
/// wire protocol, with diagnostics instead of exceptions.
///
/// Under construction: this release has the diagnostics model and the
/// protocol data types.
library;

export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/diagnostic_code.dart';
export 'src/diagnostics/diagnostic_severity.dart';
export 'src/diagnostics/diagnostic_sink.dart';
export 'src/diagnostics/source.dart';
export 'src/diagnostics/source_location.dart';
export 'src/diagnostics/source_span.dart';
export 'src/protocol/decode_result.dart';
export 'src/protocol/graphql_error.dart';
export 'src/protocol/graphql_request.dart';
export 'src/protocol/json_reader.dart';
export 'src/protocol/json_value.dart';
export 'src/protocol/path_segment.dart';
export 'src/protocol/response_payload.dart';
```

Replace `packages/typed_graphql/CHANGELOG.md` with:

```markdown
# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `Source`, `SourceLocation` and `SourceSpan`: a document, 1-based lines
  and columns computed on demand, and ranges.
- `DiagnosticCode` (the catalog, seeded with `GQL000`), `DiagnosticSeverity`,
  `Diagnostic` and `DiagnosticSink`.
- `JsonValue`, a sealed family for arbitrary JSON; `PathSegment` and
  `DecodeResult`.
- `JsonReader`: JSON text to `JsonValue`, with a nesting limit and no
  exceptions.
- `GraphQLError`: the error format of the spec, read and written.
- `GraphQLRequest` and `ResponsePayload` (`ExecutionResult`,
  `RequestErrorResult`).
```

- [ ] **Step 4: Run them to verify they pass**

Run: `(cd packages/typed_graphql && dart test test/protocol/graphql_request_test.dart test/protocol/response_payload_test.dart)`
Expected: `+19: All tests passed!` (6 + 13).

- [ ] **Step 5: Run the green check**

Expected:
- `packages/typed_graphql` ends with `+118: All tests passed!`;
- the root ends with `+34`;
- the other packages end with `+2`.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_graphql
git commit -q -m "feat(typed_graphql): add GraphQLRequest and ResponsePayload"
```

### Task 12: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the root `dart test` suite (Tasks 2–4) and every package's `dart test`, including the core's VM-only tests (`@TestOn('vm')`: `pubspec_test.dart`, `layers_test.dart`).
- Produces: the CI jobs required by R10.5:
  - `analyze`: format and analyze on stable;
  - `test`: Linux on 3.13.0 and stable, plus macOS and Windows on stable;
  - `aot`: `--compiler exe`;
  - `web`: the core with dart2js and dart2wasm;
  - `publish-dry-run`.

  The loops cover every package under `packages/`, so a new package needs no change to this file.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

# R10.5: the minimum SDK and stable; AOT; dart2js and dart2wasm; a publish
# dry-run. Formatting and lints run once, on stable: the minimum SDK only
# has to compile and pass the tests. Every package of packages/ is tested
# by the loops below, so a new package needs no change here.
jobs:
  analyze:
    name: Format and analyze
    timeout-minutes: 15
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - name: Install dependencies (workspace)
        run: dart pub get

      - name: Verify formatting
        run: dart format --output=none --set-exit-if-changed packages test

      - name: Analyze
        run: dart analyze --fatal-infos

  test:
    name: Test (${{ matrix.os }}, ${{ matrix.sdk }})
    timeout-minutes: 30
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest]
        sdk: ['3.13.0', stable]
        include:
          - os: macos-latest
            sdk: stable
          - os: windows-latest
            sdk: stable
    steps:
      - uses: actions/checkout@v5

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: ${{ matrix.sdk }}

      - name: Install dependencies (workspace)
        run: dart pub get

      - name: Test the code rules (workspace root)
        run: dart test

      - name: Test every package
        shell: bash
        run: |
          for package in packages/*/; do
            echo "::group::$package"
            (cd "$package" && dart test)
            echo "::endgroup::"
          done

  aot:
    name: Test compiled to native code (AOT)
    timeout-minutes: 30
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - name: Install dependencies (workspace)
        run: dart pub get

      - name: Test every suite with --compiler exe
        shell: bash
        run: |
          dart test --compiler exe
          for package in packages/*/; do
            echo "::group::$package"
            (cd "$package" && dart test --compiler exe)
            echo "::endgroup::"
          done

  web:
    name: Core on the web (${{ matrix.compiler }})
    timeout-minutes: 20
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        compiler: [dart2js, dart2wasm]
    steps:
      - uses: actions/checkout@v5

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - name: Install dependencies (workspace)
        run: dart pub get

      # The client joins this job when it has code that runs in a browser
      # (M11); until then its only tests are VM-only.
      - name: Test typed_graphql in Chrome
        run: dart test -p chrome --compiler ${{ matrix.compiler }}
        working-directory: packages/typed_graphql

  publish-dry-run:
    name: Publish dry-run
    timeout-minutes: 10
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - name: Install dependencies (workspace)
        run: dart pub get

      # typed_graphql_conformance is `publish_to: none` and is left out.
      - name: Dry-run every publishable package
        shell: bash
        run: |
          for package in typed_graphql typed_graphql_server typed_graphql_shelf \
            typed_graphql_client typed_graphql_codegen typed_graphql_builder; do
            echo "::group::$package"
            (cd "packages/$package" && dart pub publish --dry-run)
            echo "::endgroup::"
          done
```

- [ ] **Step 2: Check that it parses**

Run: `python3 -c 'import yaml; d = yaml.safe_load(open(".github/workflows/ci.yml")); print(sorted(d["jobs"]))'`
Expected: `['analyze', 'aot', 'publish-dry-run', 'test', 'web']`. If `actionlint` is installed, also run `actionlint .github/workflows/ci.yml`, which should print nothing.

- [ ] **Step 3: Run what the jobs run, locally**

```sh
dart format --output=none --set-exit-if-changed packages test
dart analyze --fatal-infos
dart test --compiler exe
for p in packages/*/; do (cd "$p" && dart test --compiler exe) || exit 1; done
(cd packages/typed_graphql && dart test -p chrome --compiler dart2js && dart test -p chrome --compiler dart2wasm)
```

Expected:
- the exe runs print the same counts as the green check (root `+34`, core `+118`, others `+2`);
- each Chrome run ends with `+109: All tests passed!`, because the 9 VM-only tests are skipped.

If no Chrome is installed, skip the last line; CI runs it.

- [ ] **Step 4: Run the green check**

Expected: the same counts as at the end of Task 11.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml
git commit -q -m "ci: add the CI workflow"
```

### Task 13: Process and user documents

**Files:**
- Create: `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, `docs/superpowers/HANDOFF.md`
- Modify: `docs/README.md` (replace it whole), `packages/typed_graphql/README.md` (replace it whole)

**Interfaces:**
- Consumes: every public name from Tasks 6–11, the commands from "The green check" and Task 12, and the rules enforced by Tasks 4 and 5. The documents must name them exactly.
- Produces (R11.4):
  - `CLAUDE.md`: the binding repository guide;
  - `CONTRIBUTING.md`;
  - the root `README.md` in basalt's skeleton;
  - `docs/superpowers/HANDOFF.md`, which shows M1 "in progress" (Task 14 updates it);
  - the docs index;
  - the full core README.

  The README examples compile and print what the READMEs say.

- [ ] **Step 1: Write the repository guide**

Create `CLAUDE.md`:

````markdown
# CLAUDE.md

Guidance for working in this repository. It is binding for people and agents.

## Project

`typed_graphql` is a from-scratch GraphQL implementation for Dart: the whole
specification (September2025 edition) and its protocols, fully typed on the
server and the client. It is a Dart pub workspace of pure-Dart packages:

| Package | Role | Stage |
|---|---|---|
| `packages/typed_graphql` | Core: `diagnostics/`, `language/`, `protocol/`, `schema/`, `validation/`; depends only on `meta` | M1–M4 |
| `packages/typed_graphql_server` | Typed schema builder, executor, request pipeline, transport handlers | M5–M7 |
| `packages/typed_graphql_shelf` | `shelf` adapter (HTTP, WebSocket, GraphiQL in development) | M7 |
| `packages/typed_graphql_client` | Client runtime: links, transports, normalized cache | M11–M12 |
| `packages/typed_graphql_codegen` | Code generation engine and CLI, without `analyzer` | M8, M10 |
| `packages/typed_graphql_builder` | `build_runner` builders; the only `analyzer` user | M9 |
| `packages/typed_graphql_conformance` | `publish_to: none`: ported graphql-js suites, fuzzers, benchmarks | M2 on |

Minimum SDK: Dart 3.13 (`sdk: ^3.13.0`) in every package and in generated
code. No dependency on `package:gql` or its ecosystem.

Status: under construction. M1 (foundations) delivers the workspace, the code
rules, CI, the diagnostics model and the protocol data types.

## Documents

- `docs/requirements.md` - requirements R0–R11; quote their ids in specs,
  plans and tests.
- `docs/roadmap.md` - stages M1–M16 and the rules for plans.
- `docs/superpowers/specs/2026-10-13-typed-graphql-design.md` - the
  architecture; a stage spec refines it, never overrides it silently.
- `docs/superpowers/plans/` - one plan per stage; `HANDOFF.md` - where the
  work stands and the rules the user set. Read it first in a new session.
- `docs/research/` - the research and the decisions log (`README.md`).
- `reference/` (git-ignored) - the specifications, protocols and graphql-js;
  fetch them with `tool/fetch_reference.sh`. Never edit it.

## Commands

```sh
dart pub get                                                   # repo root, once and after pubspec edits
dart format --output=none --set-exit-if-changed packages test  # must change 0 files
dart analyze --fatal-infos                                     # repo root; must print "No issues found!"
dart test                                                      # repo root: the code rules
cd packages/typed_graphql && dart test                         # one package (every package has tests)
cd packages/typed_graphql && dart test --compiler exe          # AOT (sealed switches, sdk#56010)
cd packages/typed_graphql && dart test -p chrome --compiler dart2js
cd packages/typed_graphql && dart test -p chrome --compiler dart2wasm
cd packages/<package> && dart pub publish --dry-run            # never without --dry-run
```

Git commands run from the repo root. Commits are Conventional Commits with the
package as the scope: `feat(typed_graphql): ...`, `test(workspace): ...`,
`ci: ...`, `docs: ...`, `refactor(...)`.

## Architecture

**Core layers.** `packages/typed_graphql/lib/src/` has one folder per layer,
lowest first: `diagnostics`, `language`, `protocol`, `schema`, `validation`. A
library imports only its own layer and the layers before it; the core imports
no platform library but `dart:async`, `dart:collection`, `dart:convert`,
`dart:core`, `dart:math`, `dart:typed_data`, and no package but `meta`.
`test/quality/layers_test.dart` enforces this (R0.6, R10.2). Libraries in
`lib/src/` import each other with relative paths, never through the barrel.

**Diagnostics** (`diagnostics/`).
- `Source(body, name:)` holds a document; `locationOf(offset)` gives a
  1-based `SourceLocation` (column in UTF-16 code units). The table of line
  starts is built on the first call. `\r\n`, `\n` and `\r` end a line.
- `SourceSpan(source, start, end)` is a range of offsets; a diagnostic points
  at one.
- `DiagnosticCode` is the catalog: one enum value per problem, id `GQLnxx`,
  a doc comment that says when it is reported. Ids are public API: never
  renumber, reuse or remove one. Ranges: `GQL0xx` syntax, `GQL1xx` type
  system, `GQL2xx` operation validation, `GQL3xx` coercion and execution,
  `GQL4xx` transports, `GQL5xx` code generation; `GQL000` is the sink limit.
- `Diagnostic(code, severity, message, span:, related:)`.
- `DiagnosticSink` collects diagnostics in report order and stops after
  `maxErrors` errors (default 100) with one `GQL000`. Lexer, parser and rules
  take a sink through their constructor; the public API turns it into a
  sealed result.

**Protocol** (`protocol/`).
- `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
  `JsonString`, `JsonArray`, `JsonObject`): the type of arbitrary JSON in
  every public signature (R0.2). Values compare by value; `1` equals `1.0`;
  `JsonNumber.asInt` is the safe-integer view.
- `JsonReader` turns untrusted text or `jsonDecode` output into a
  `JsonValue`, or a `DecodeFailure` with a path (non-finite numbers, too deep
  nesting, non-JSON objects).
- `DecodeResult<T>` = `DecodeSuccess<T>(value)` | `DecodeFailure(message,
  path:)`; `inside(segment)` prefixes the path. `PathSegment` =
  `PathKey(name)` | `PathIndex(index)`.
- `GraphQLError`, `GraphQLRequest` and `ResponsePayload` (`ExecutionResult` |
  `RequestErrorResult`) read with a static `decode(JsonValue)` and write with
  `toJson()`; equality is equality of their JSON.

**Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
`DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
`ArgumentError`, `RangeError`, `StateError`.

## Code rules

The rules of typed_openapi, with its `analysis_options.yaml` verbatim (R10.1).
The workspace suite in `test/quality/` (run `dart test` at the root) enforces
what a lint cannot (R10.2).

**Limits** (all lines count, comments and blanks included: use `wc -l`):

| Unit | Limit | Checked by |
|---|---|---|
| File in `lib/` or `bin/` | 300 lines | ratchet, allowlist may only shrink |
| File in `test/` or `tool/` | 500 lines | ratchet |
| Method, getter, operator, constructor in `lib/` | 40 lines | ratchet |
| Parameters of a method in `lib/` | 5 (constructors exempt) | rule |
| Nesting of `if`/`for`/`while`/`switch`/`try` | 3 levels | rule |
| Public types per file in `lib/` | one public class or sealed family | rule |

Allowed by no exception: `part` files, top-level functions other than
`main`, `utils`/`helpers`/`common`/`misc` files in `lib/`, `dynamic`, a
`catch` without `on`. Permanently exempt from the size limit: the catalog
`diagnostics/diagnostic_code.dart`. Nothing else is exempt; the allowlists in
`test/quality/code_rules_test.dart` start empty and stay so.

**Before you write.** Run `wc -l` on the file you are about to extend. If the
change would take it past the limit, extract first, in its own commit.

**How to decompose.** Split by responsibility into collaborator classes, one
per file, in the layer folder. A helper made public to leave a file stays out
of the barrel unless it is API. No hidden state passed through fields: pass a
parameter or a small immutable object. Do not abstract for a future need.

**Readability.** Names say what a thing is or does; no abbreviations, no
`Helper`/`Manager`/`Impl`. Booleans read as a state (`isFull`, `hasErrors`).
A comment says why (a spec section, a requirement id, a trap), never what.
Prefer a `switch` over a sealed type or a record to `is` chains; no `!` where
a pattern can promote; no `late` without a comment on why it is set before it
is read.

**Dart 3.13.** Use primary constructors, dot shorthands, null-aware elements
(`'key': ?value`), patterns, records, sealed and `final` classes. Learned in
M1:
- `public_member_api_docs` reports an undocumented primary constructor: give
  the class a body with a documented `this;`.
- `@immutable` only on a class whose constructors can all be `const`, or
  `prefer_const_constructors_in_immutables` fires; subclasses inherit it.
- A non-late field initializer can read a non-declaring parameter
  (`final List<T> items = List.unmodifiable(items);`); a `late` one cannot.
- `==` of a generic class checks `is C<Object?>`, not `is C<T>`, or two equal
  values with different static types differ.
- In tests, `expect` arguments have no context type: write full names, not
  dot shorthands.

**Dart style the lints do not check.** Acronyms longer than two letters are
words (`Json`, `Sse`); doc comments start with a one-sentence summary and
refer to identifiers in `[brackets]`; a boolean property starts with
"Whether"; never silence a lint (`// ignore:` is not used); no nullable
`Future`, `Stream` or collection return; never catch `Error`.

**Tests.** Tests come in the same commit as the code; a new branch of logic
has a test that fails without it. A test names the behaviour and checks one
thing. Tests that need `dart:io` start with `@TestOn('vm')`, because the core
suite also runs in Chrome. Every package keeps at least one test: `dart test`
fails when it finds none.

**Self-review before saying "done".**
1. `wc -l` of every file touched, and the longest method added.
2. Could a new reader say in one sentence what each new class and method is
   for? If not, rename or split.
3. Is there code, a parameter or a flag nothing uses yet? Remove it.
4. Format, analyze and every affected suite are clean, and `CLAUDE.md`,
   `docs/` and the package `CHANGELOG.md` say what changed.

## Design rules

- **Nothing is guessed silently.** Every problem in user input is a
  diagnostic with a stable code and a place, or a `DecodeFailure` with a
  path.
- **A new diagnostic code** goes into `DiagnosticCode` in id order, with a
  doc comment, in the commit that first reports it.
- **No `dynamic`, no `Map<String, dynamic>`** in a public signature;
  arbitrary JSON is `JsonValue`.
- **The core stays pure Dart** and runs on the VM, AOT, dart2js and
  dart2wasm. `analyzer` is used only by `typed_graphql_builder`.
- **Dependencies arrive with the stage that first uses them.** M1 declares
  only workspace packages, `meta`, `test` and `lints`.
- **Conformance is measured.** A ported graphql-js test is recorded in the
  conformance mapping table in the same commit (from M2).
- **Deterministic output.** Printers and generators sort what they emit and
  never iterate a hash-ordered collection.

## Process

- One stage = one design spec and one plan in `docs/superpowers/`. Plans hold
  all the code, checked before they are written; tasks are TDD, one commit
  each, and every task leaves the tree green.
- Repository text is English. User-facing changes go into the package's
  `CHANGELOG.md` (`## 0.0.1 - Unreleased`, `- **Breaking:** ...` for breaking
  entries).
- Outward actions (pushing, tags, publishing, issues, PRs) need the user's
  explicit yes. `dart pub publish` runs only with `--dry-run`.

## Where things are

- Code rules suite: `test/quality/` at the workspace root (`code_rules.dart`
  and its scanners).
- Core layer test: `packages/typed_graphql/test/quality/layers_test.dart`.
- Diagnostic catalog: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`.
- CI: `.github/workflows/ci.yml`.
````

Create `CONTRIBUTING.md`:

````markdown
# Contributing to typed_graphql

## Contents

- [Prerequisites](#prerequisites)
- [Getting the code](#getting-the-code)
- [Repository layout](#repository-layout)
- [Everyday commands](#everyday-commands)
- [Design rules](#design-rules)
- [Coding conventions](#coding-conventions)
- [Dart 3.13](#dart-313)
- [Tests](#tests)
- [Diagnostic codes](#diagnostic-codes)
- [Commits and pull requests](#commits-and-pull-requests)

## Prerequisites

- Dart SDK 3.13 or newer (`sdk: ^3.13.0`). Every package is pure Dart;
  Flutter is not needed.
- Google Chrome, to run the core's tests compiled to JavaScript and Wasm.

## Getting the code

This repository is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces):
all packages resolve together from one lockfile. Run this once from the
repository root:

```sh
dart pub get
```

## Repository layout

The packages are listed in the [root README](README.md#packages). Requirements,
the roadmap, the architecture spec and the research are in [docs/](docs/);
[CLAUDE.md](CLAUDE.md) is the full guide to the code and its rules.

## Everyday commands

From the repository root unless noted:

```sh
dart format packages test
dart analyze --fatal-infos
dart test                                   # the code rules of the whole workspace

cd packages/typed_graphql && dart test      # and likewise for every package
cd packages/typed_graphql && dart test --compiler exe
cd packages/typed_graphql && dart test -p chrome --compiler dart2js
cd packages/typed_graphql && dart test -p chrome --compiler dart2wasm

# Before a release, for each publishable package:
cd packages/<package> && dart pub publish --dry-run
```

## Design rules

- **Bad input never throws.** Parsing, validation, coercion and decoding
  return sealed results that carry every diagnostic. Exceptions are for
  programmer errors (`ArgumentError`, `RangeError`, `StateError`).
- **Every problem has a stable code** from the `DiagnosticCode` catalog and a
  place in the source, or a path in the JSON.
- **Fully typed.** No `dynamic` and no `Map<String, dynamic>` in a public
  signature; arbitrary JSON is `JsonValue`.
- **The core is pure Dart.** `typed_graphql` depends only on `meta`, imports
  no `dart:io`, and runs on the VM, AOT, dart2js and dart2wasm. Its layers
  import downwards only: `diagnostics`, `language`, `protocol`, `schema`,
  `validation`.
- **Independent of `package:gql`.** No dependency on it or its ecosystem.
- **`analyzer` only in `typed_graphql_builder`.**

## Coding conventions

`analysis_options.yaml` (on `package:lints/recommended.yaml`) is enforced
with `--fatal-infos`; every public member has a doc comment. The workspace
suite in `test/quality/` enforces the rest:

- files in `lib/` at most 300 lines, test files at most 500, methods at most
  40, at most 5 parameters per method, control blocks nested at most 3 deep;
- one public class or sealed family per file in `lib/`;
- no `part` files, no top-level functions except `main`, no `utils` or
  `helpers` files, no `dynamic`, no `catch` without `on`.

Components that report problems take a `DiagnosticSink` through their
constructor. Never silence a lint with `// ignore:`.

## Dart 3.13

Use the stable 3.13 features where they fit: primary constructors, dot
shorthands (`.error`), null-aware elements (`'key': ?value`), switch
expressions and patterns, records, class modifiers. Give a primary
constructor a documented `this;` body so `public_member_api_docs` passes. In
tests, `expect(...)` arguments have no context type, so use full names there.

## Tests

- Tests come with the code, in the same commit; a new branch of logic has a
  test that fails without it.
- A test that needs `dart:io` starts with `@TestOn('vm')`: the core suite
  also runs in Chrome.
- Ported graphql-js tests (from M2) are listed in the conformance mapping
  table in the same commit.

## Diagnostic codes

A new code goes into `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`
in id order, with a doc comment that says when it is reported. Ids are
public API: never renumber, reuse or remove one.

## Commits and pull requests

- Branch off `main`. Commit messages are Conventional Commits with the
  package as the scope (`feat(typed_graphql): ...`).
- Before pushing: format, analyze, and the suites of the packages you
  touched, plus `dart test` at the root.
- Add a line to the affected package's `CHANGELOG.md` for every user-facing
  change; mark a breaking one `**Breaking:**`.
````

- [ ] **Step 2: Write the READMEs**

Create `README.md`:

````markdown
# typed_graphql

[![CI](https://github.com/4akloon/graphql_dart/actions/workflows/ci.yml/badge.svg)](https://github.com/4akloon/graphql_dart/actions/workflows/ci.yml)
![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Status](https://img.shields.io/badge/status-under%20construction-orange)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

**GraphQL for Dart, written from scratch and fully typed: the whole
September2025 specification and its protocols, on the server and on the
client, with diagnostics instead of exceptions.**

What it is built to be (see the [roadmap](docs/roadmap.md)):

- 🧾 **Spec-complete language** — an error-resilient parser that reports every
  syntax error in one pass, a sealed AST, a printer and visitors (M2).
- 🧱 **Type system and validation** — SDL and introspection to a validated
  schema, all 30 validation rules in one walk (M3, M4).
- 🖥️ **Typed server** — a typed schema builder, a `FutureOr` executor,
  subscriptions, DataLoader, GraphQL over HTTP, graphql-ws and graphql-sse
  (M5–M9).
- 📱 **Typed client** — operation-based code generation, links, a normalized
  cache (M10–M12).
- 🚫 **No `dynamic`, no exceptions on bad input** — sealed results that carry
  every diagnostic, each with a stable code.

What works today: the diagnostics model and the wire protocol types.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const body = '''
{
  "errors": [
    {
      "message": "Name for character with ID 1002 could not be fetched.",
      "locations": [{"line": 6, "column": 7}],
      "path": ["hero", "heroFriends", 1, "name"]
    }
  ],
  "data": {"hero": {"name": "R2-D2", "heroFriends": [null, null]}}
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
}
```

> **Status: under construction.** Nothing is published to pub.dev yet, and
> every API may change before 0.1.0. Stage M1 (foundations) is the current
> one; the parser arrives in M2.

## Table of contents

- [Why typed_graphql](#why-typed_graphql)
- [Packages](#packages)
- [Install](#install)
- [Getting started](#getting-started)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Why typed_graphql

No Dart package implements GraphQL as a whole. `package:gql` is tooling
without execution or introspection, the server packages are not
spec-complete, and `@defer` / `@stream` exist nowhere in Dart
([research](docs/research/README.md)). typed_graphql takes the design every
serious implementation converged on: a hand-written error-resilient parser,
typestate for validated schemas and documents, validation rules fused into
one walk, a synchronous fast path in the executor, and document-first,
operation-based client code generation.

- **Typed end to end.** Arbitrary JSON is `JsonValue`, a sealed family you
  can switch over; there is no `dynamic` in any public signature.
- **Every problem at once.** Parsing and validation report every diagnostic
  with a stable code (`GQL0xx`–`GQL5xx`) and a source location.
- **Conformance is measured.** The graphql-js v17 suites are ported with a
  mapping table, and every suite also runs AOT-compiled and in the browser.
- **Independent.** No dependency on `package:gql`; the core is pure Dart and
  depends only on `meta`.

## Packages

This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.

| Package | Role | Status |
|---|---|---|
| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics and protocol types (M1) |
| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
| [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
| [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
| [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | skeleton (M8, M10) |
| [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | skeleton (M2) |

## Install

Nothing is on pub.dev yet. To try the core from this repository:

```yaml
dependencies:
  typed_graphql:
    git:
      url: https://github.com/4akloon/graphql_dart
      path: packages/typed_graphql
```

## Getting started

The core reads untrusted JSON into typed values and never throws on bad
input:

- `JsonReader().parse(text)` gives a `JsonValue`, or a `DecodeFailure` that
  says where the input is wrong (`$.errors[0].message: expected a string`).
- `GraphQLRequest.decode`, `GraphQLError.decode` and `ResponsePayload.decode`
  read the GraphQL wire format; `toJson()` writes it.
- `Source`, `SourceSpan`, `Diagnostic` and `DiagnosticSink` are the
  diagnostics model the parser and validator will report through.

## Documentation

- [Roadmap](docs/roadmap.md) · [Requirements](docs/requirements.md) ·
  [Architecture](docs/superpowers/specs/2026-10-13-typed-graphql-design.md)
- [Research and decisions](docs/research/README.md)
- [CLAUDE.md](CLAUDE.md) — the repository guide for contributors and AI agents

## Contributing

Setup, commands, the design rules and the coding conventions are in
**[CONTRIBUTING.md](CONTRIBUTING.md)**. The short version:

```sh
dart pub get
dart analyze --fatal-infos
dart test && (cd packages/typed_graphql && dart test)
```

## License

MIT — see [LICENSE](LICENSE).
````

Replace `packages/typed_graphql/README.md` with:

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

> **Status: under construction.** This release has the diagnostics model and
> the protocol data types. The parser arrives in M2, the type system in M3 and
> validation in M4 (see the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).

## Contents

- [Install](#install)
- [Reading the wire format](#reading-the-wire-format)
- [Diagnostics](#diagnostics)
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

## Reading the wire format

Bad input never throws. `JsonReader` turns text into a `JsonValue`, a sealed
family you can switch over; the `decode` methods turn a `JsonValue` into
`GraphQLRequest`, `GraphQLError` or `ResponsePayload`. Each step gives a
`DecodeResult`: a `DecodeSuccess`, or a `DecodeFailure` that says where the
input is wrong.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const reader = JsonReader();

  // A request body from the wire: unknown keys are ignored.
  final request = switch (reader.parse('{"query": "{ hero { name } }"}')) {
    DecodeSuccess(:final value) => GraphQLRequest.decode(value),
    final DecodeFailure failure => failure,
  };
  print(request);

  // A failure says where the input is wrong.
  final response = switch (reader.parse('{"errors": [{"message": 7}]}')) {
    DecodeSuccess(:final value) => ResponsePayload.decode(value),
    final DecodeFailure failure => failure,
  };
  print(response);

  // Spans turn offsets into lines and columns.
  final source = Source('{\n  hero\n}', name: 'hero.graphql');
  print(SourceSpan(source, 4, 8));
}
```

It prints:

```text
DecodeSuccess(GraphQLRequest({"query":"{ hero { name } }"}))
$.errors[0].message: expected a string
hero.graphql:2:3
```

`JsonReader` rejects input nested deeper than `maxDepth` (512 by default)
before decoding it, and numbers too large to be finite. A `ResponsePayload`
is an `ExecutionResult` (it has `data`, maybe `null`) or a
`RequestErrorResult` (no `data`, at least one error).

## Diagnostics

The parser and the validator will report through this model:

- `Source` is a document and its name; `locationOf(offset)` gives a 1-based
  line and column, counted in UTF-16 code units.
- `SourceSpan` is a range of a `Source`.
- `Diagnostic` is one problem: a `DiagnosticCode` with a stable id
  (`GQL000`), a severity, a message, a span and related spans.
- `DiagnosticSink` collects diagnostics in order and stops at `maxErrors`
  errors (100 by default), reporting `GQL000` once.

## License

MIT — see [LICENSE](LICENSE).
````

- [ ] **Step 3: Write the handoff and the docs index**

Create `docs/superpowers/HANDOFF.md`:

```markdown
# Handoff: where typed_graphql stands and how to continue

Last updated: 2026-10-13 (M1 in progress). Read this first on a new device or
in a new Claude session. Session memory and scratch directories do not
travel; this file and the repository hold everything needed.

## State

| Stage | Design | Plan | Code |
|---|---|---|---|
| Architecture | [spec](specs/2026-10-13-typed-graphql-design.md), [requirements](../requirements.md), [roadmap](../roadmap.md) | — | — |
| M1 Foundations | the architecture spec (no stage spec) | [plan](plans/2026-10-13-m1-foundations.md) | in progress |
| M2 Language | next: write `specs/…-m2-language-design.md` | — | — |

**Open questions for the user** (raised by the M1 plan):
- The layer arrow `protocol ← diagnostics, language` in spec §1 is read as
  "protocol depends on diagnostics and language", giving the order
  diagnostics < language < protocol < schema < validation. Confirm, or the
  layer test changes.
- Spec principle 2 calls `JsonValue` an extension type; M1 made it a sealed
  class family (an extension type cannot be sealed or matched with `is`).
  Amend the spec.
- Spec §2 lists `Source` under the language layer; M1 put it in
  `diagnostics/`, the lowest layer, because `Diagnostic` needs spans.

## How a stage is done

The superpowers skills: `brainstorming`, `writing-plans`,
`subagent-driven-development`.

1. **Design.** Ask the user one question at a time, each with a recommended
   option, in Ukrainian. Write the stage spec in English under
   `docs/superpowers/specs/` and commit it on main.
2. **Plan.** An Opus agent writes the plan from the spec. Every code block is
   checked in a scratch workspace before it goes into the plan. Bring the
   plan's open questions to the user, then commit the plan on main.
3. **Implement.** Create a worktree from main on a branch such as
   `feat/m2-language`. For each task, one fresh Sonnet implementer, then a
   Sonnet reviewer of that task. One implementer at a time.
4. **Final review.** An Opus review of the whole branch, one fix round, and a
   scoped re-review. Residuals go into `docs/roadmap.md` with a reason.
5. **Merge.** `git merge --no-ff` into main, re-run every suite on the merged
   tree, remove the worktree and the branch, update this file.

## Rules the user set

- **Outward actions need the user's explicit yes:** pushing to GitHub, tags,
  publishing to pub.dev, creating issues or PRs. `dart pub publish` runs only
  with `--dry-run`.
- **Models.** Sonnet for implementers and reviewers, never Haiku. Opus for
  designs, plans and final reviews.
- **Language.** Talk with the user in Ukrainian. Everything in the repository
  is English.
- **Code quality.** `CLAUDE.md` is binding. The ratchet in `test/quality/`
  holds files in `lib/` to 300 lines, test files to 500, methods to 40.
  Allowlists start empty and never grow. No `// ignore:` anywhere.
- **Style references.** typed_openapi for code rules and process documents,
  basalt for user documentation (README skeleton, `doc/*.md` guides,
  CHANGELOG format).

## Repository

- Remote: https://github.com/4akloon/graphql_dart (`main`).
- CI: `.github/workflows/ci.yml` (format and analyze; tests on 3.13.0 and
  stable on Linux, stable on macOS and Windows; AOT; the core in Chrome with
  dart2js and dart2wasm; publish dry-run).
- `reference/` is git-ignored; `tool/fetch_reference.sh` fetches it.
```

Replace `docs/README.md` with:

```markdown
# Design docs

| Document | Contents |
|---|---|
| `superpowers/HANDOFF.md` | Where the project stands, how a stage is done, the user's rules; read first |
| `requirements.md` | Requirements R0–R11 with tags and owning stages |
| `roadmap.md` | Stages M1–M16: scope, requirement IDs, dependencies |
| `superpowers/specs/` | The architecture spec and one design spec per stage |
| `superpowers/plans/` | Step-by-step implementation plans, one per stage |
| `research/README.md` | Research summary and the decisions log |
| `research/01…05-*.md` | Detailed reports with primary sources |
| `../CLAUDE.md` | The repository guide: packages, commands, architecture, code rules |
| `../CONTRIBUTING.md` | Setup, checks and conventions for contributors |

All documents are written in English. The specifications and protocols the
research cites live in the git-ignored `reference/` folder; fetch them with
`tool/fetch_reference.sh`.
```

- [ ] **Step 4: Check that the README examples compile and print what they claim**

```sh
mkdir -p packages/typed_graphql/example
awk '/^```dart$/{f=1;next} /^```$/{f=0} f' packages/typed_graphql/README.md > packages/typed_graphql/example/core_readme.dart
awk '/^```dart$/{f=1;next} /^```$/{f=0} f' README.md > packages/typed_graphql/example/root_readme.dart
(cd packages/typed_graphql && dart run example/core_readme.dart && dart run example/root_readme.dart)
rm -r packages/typed_graphql/example
```

Expected output, exactly:

```text
DecodeSuccess(GraphQLRequest({"query":"{ hero { name } }"}))
$.errors[0].message: expected a string
hero.graphql:2:3
data: {"hero":{"name":"R2-D2","heroFriends":[null,null]}}
first error at [hero, heroFriends, 1, name]
```

After the `rm`, `git status --short` lists only this task's documents.

- [ ] **Step 5: Check the six publishable packages again**

The core README changed, so run the dry-run loop from Task 1, Step 11 again. The working tree has uncommitted changes at this point, which `pub` may mention as a hint.
Expected: "Package has 0 warnings." for each package.

- [ ] **Step 6: Run the green check**

Expected: the same counts as at the end of Task 11. The documents are not Dart, so nothing else changes.

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md CONTRIBUTING.md README.md docs/README.md docs/superpowers/HANDOFF.md packages/typed_graphql/README.md
git commit -q -m "docs: add CLAUDE.md, CONTRIBUTING.md, the handoff and the READMEs"
```

### Task 14: Full verification and the handoff update

**Files:**
- Modify: `docs/superpowers/HANDOFF.md` (replace it whole)

**Interfaces:**
- Consumes: everything from Tasks 1–13.
- Produces: the evidence that M1 is done, and a handoff that says so.

- [ ] **Step 1: Run every suite the way CI does**

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages test
dart analyze --fatal-infos
dart test
for p in packages/*/; do (cd "$p" && dart test) || exit 1; done
dart test --compiler exe
for p in packages/*/; do (cd "$p" && dart test --compiler exe) || exit 1; done
(cd packages/typed_graphql && dart test -p chrome --compiler dart2js && dart test -p chrome --compiler dart2wasm)
```

Expected:
- the root `+34`;
- the core `+118`, on the VM and as exe;
- the six other packages `+2`;
- Chrome `+109` with each compiler;
- format and analyze clean.

- [ ] **Step 2: Check that both ratchets bite**

```sh
printf "import '../protocol/json_value.dart';\n\n/// A probe.\nfinal class Probe {}\n" > packages/typed_graphql/lib/src/diagnostics/probe.dart
(cd packages/typed_graphql && dart test test/quality/layers_test.dart)
rm packages/typed_graphql/lib/src/diagnostics/probe.dart
python3 -c "print('/// A probe.\nfinal class Probe {}\n' + '\n' * 300)" > packages/typed_graphql_client/lib/probe.dart
dart test test/quality/code_rules_test.dart
rm packages/typed_graphql_client/lib/probe.dart
```

Expected:
- the layer test fails with `diagnostics/probe.dart imports ../protocol/json_value.dart: diagnostics must not depend on protocol`;
- the ratchet fails with `packages/typed_graphql_client/lib/probe.dart has 303 lines, over its limit`;
- afterwards `git status --short` prints nothing.

- [ ] **Step 3: Check that the six publishable packages would publish**

Run the loop from Task 1, Step 11.
Expected: "Package has 0 warnings." six times. Never run `dart pub publish` without `--dry-run`.

- [ ] **Step 4: Check that nothing outside M1's dependencies came in**

Run: `grep -h -A3 '^dependencies:' packages/*/pubspec.yaml | grep -v '^dependencies:\|^--$\|^$' | sort -u`
Expected: only `meta: ^1.15.0`, the workspace packages (`typed_graphql…`), and `dev_dependencies:` lines.

Run: `grep -rln "dart:io" packages/typed_graphql/lib || echo "no dart:io"`
Expected: `no dart:io` (R0.6).

- [ ] **Step 5: Record the result in the handoff**

Replace `docs/superpowers/HANDOFF.md` with:

```markdown
# Handoff: where typed_graphql stands and how to continue

Last updated: 2026-10-13 (M1 implemented, final review pending). Read this
first on a new device or in a new Claude session. Session memory and scratch
directories do not travel; this file and the repository hold everything
needed.

## State

| Stage | Design | Plan | Code |
|---|---|---|---|
| Architecture | [spec](specs/2026-10-13-typed-graphql-design.md), [requirements](../requirements.md), [roadmap](../roadmap.md) | — | — |
| M1 Foundations | the architecture spec (no stage spec) | [plan](plans/2026-10-13-m1-foundations.md) | implemented on the M1 branch; final review and merge pending |
| M2 Language | next: write `specs/…-m2-language-design.md` | — | — |

**Open questions for the user** (raised by the M1 plan):
- The layer arrow `protocol ← diagnostics, language` in spec §1 is read as
  "protocol depends on diagnostics and language", giving the order
  diagnostics < language < protocol < schema < validation. Confirm, or the
  layer test changes.
- Spec principle 2 calls `JsonValue` an extension type; M1 made it a sealed
  class family (an extension type cannot be sealed or matched with `is`).
  Amend the spec.
- Spec §2 lists `Source` under the language layer; M1 put it in
  `diagnostics/`, the lowest layer, because `Diagnostic` needs spans.

## How a stage is done

The superpowers skills: `brainstorming`, `writing-plans`,
`subagent-driven-development`.

1. **Design.** Ask the user one question at a time, each with a recommended
   option, in Ukrainian. Write the stage spec in English under
   `docs/superpowers/specs/` and commit it on main.
2. **Plan.** An Opus agent writes the plan from the spec. Every code block is
   checked in a scratch workspace before it goes into the plan. Bring the
   plan's open questions to the user, then commit the plan on main.
3. **Implement.** Create a worktree from main on a branch such as
   `feat/m2-language`. For each task, one fresh Sonnet implementer, then a
   Sonnet reviewer of that task. One implementer at a time.
4. **Final review.** An Opus review of the whole branch, one fix round, and a
   scoped re-review. Residuals go into `docs/roadmap.md` with a reason.
5. **Merge.** `git merge --no-ff` into main, re-run every suite on the merged
   tree, remove the worktree and the branch, update this file.

## Rules the user set

- **Outward actions need the user's explicit yes:** pushing to GitHub, tags,
  publishing to pub.dev, creating issues or PRs. `dart pub publish` runs only
  with `--dry-run`.
- **Models.** Sonnet for implementers and reviewers, never Haiku. Opus for
  designs, plans and final reviews.
- **Language.** Talk with the user in Ukrainian. Everything in the repository
  is English.
- **Code quality.** `CLAUDE.md` is binding. The ratchet in `test/quality/`
  holds files in `lib/` to 300 lines, test files to 500, methods to 40.
  Allowlists start empty and never grow. No `// ignore:` anywhere.
- **Style references.** typed_openapi for code rules and process documents,
  basalt for user documentation (README skeleton, `doc/*.md` guides,
  CHANGELOG format).

## Repository

- Remote: https://github.com/4akloon/graphql_dart (`main`).
- CI: `.github/workflows/ci.yml` (format and analyze; tests on 3.13.0 and
  stable on Linux, stable on macOS and Windows; AOT; the core in Chrome with
  dart2js and dart2wasm; publish dry-run).
- `reference/` is git-ignored; `tool/fetch_reference.sh` fetches it.
```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/HANDOFF.md
git commit -q -m "docs: record M1 as implemented in the handoff"
```

---

## Requirement coverage

The M1 row of `docs/roadmap.md` lists these requirements. Each is quoted from `docs/requirements.md` and mapped to the tasks and tests that meet it.

| Id | Requirement (verbatim) | Where it is met |
|---|---|---|
| R0.5 | `sdk: ^3.13.0` in every package and in generated code; stable Dart 3.13 features are used, no experiment flags | Task 1: every pubspec and `test/pubspec_test.dart` (`requires Dart 3.13 (R0.5)`) in all seven packages. Primary constructors and dot shorthands are used from Task 2 on, with no `--enable-experiment`. CI tests on 3.13.0 (Task 12). Generated code starts in M8/M10. |
| R0.6 | The core package is pure Dart: no `dart:io`, no dependencies except `meta`; it compiles with dart2js and dart2wasm | Task 1: the core pubspec has only `meta`. Task 5: `rejects dart:io and packages other than meta`, `lib/src follows the layer rule`. Tasks 9, 12 and 14: the core passes in Chrome with dart2js and dart2wasm. |
| R1.7 (Source) | Every node has `start`/`end` offsets; `Source` computes line/column lazily | M1 has the `Source` part. Task 6: `Source.locationOf` builds the line table on the first call (`late final _lineStarts`), and `SourceSpan` carries `start`/`end` offsets. AST nodes get them in M2. |
| R1.12 | Stable `DiagnosticCode` catalog with ranges `GQL0xx`–`GQL5xx`, each code documented | Task 7: `DiagnosticCode`, with the range table in its doc comment and `GQL000` documented. Tests: `every id is GQL and three digits`, `ids are unique and sorted`, `keeps the ids already published`. `public_member_api_docs` makes every new code carry a doc comment. |
| R10.1 | typed_openapi code rules; its `analysis_options.yaml` verbatim | Task 1: the verbatim `analysis_options.yaml`. Task 4: the code rules of `CLAUDE.md` (limits, no `part`, no `dynamic`, no catch without `on`, no top-level functions, one public type per file, no grab-bag names). Task 13: `CLAUDE.md` and `CONTRIBUTING.md` state them. |
| R10.2 | Size-limit ratchet and core layer-direction tests | Task 4: `code_rules_test.dart`, with empty allowlists that only shrink. Task 5: `layers_test.dart`. Task 14, Step 2 proves that both fail on a violation. |
| R10.5 | CI: minimum SDK + stable; AOT runs; dart2js and dart2wasm for the core and the client; publish dry-run | Task 12: `ci.yml`, with the jobs `test` (3.13.0 and stable), `aot`, `web` (core) and `publish-dry-run`. The client joins `web` in M11 (finding 8). |
| R11.4 | Process documents in English (`docs/`), `CLAUDE.md`, `CONTRIBUTING.md` | Task 13: `CLAUDE.md`, `CONTRIBUTING.md`, `docs/superpowers/HANDOFF.md`, the `docs/README.md` index. Task 14 updates the handoff. |

The roadmap's M1 row also lists items that are not requirement ids. Each one has a task:

| Roadmap item | Task |
|---|---|
| Workspace with all package skeletons | 1 |
| Old `lib/`, `example/`, `test/` deleted | 1 |
| typed_openapi `analysis_options.yaml` | 1 |
| Ratchet tests | 2–5 |
| CI | 12 |
| `Source` with a lazy line table and spans | 6 |
| The catalog, `Diagnostic`, `DiagnosticSink` | 7 |
| `protocol/` data types | 8–11 |
| `CLAUDE.md`, `CONTRIBUTING.md`, `HANDOFF.md` | 13 |

## Self-review

1. **Spec coverage.** Every M1 item in the roadmap row and every requirement id above maps to a task. Two parts are deferred on purpose:
   - R1.7 beyond `Source` (node offsets) belongs to M2;
   - R10.5 for the client waits until the client has code (M11); finding 8 records this.
2. **Placeholder scan.** The plan has no "TBD", no "similar to Task N" and no step without its code. Every file is given whole. The barrel and the core changelog are given whole in each task that changes them. The three files that are identical in every package (`LICENSE`, `CHANGELOG.md`, `test/pubspec_test.dart`) are given once and copied by an explicit loop.
3. **Type consistency.** Every code block was copied from a scratch workspace in which:
   - `dart format` and `dart analyze --fatal-infos` are clean;
   - the root suite (34 tests) and the core suite (118 tests) pass on the VM and as exe;
   - the core passes in Chrome (109 tests) with dart2js and dart2wasm;
   - the six dry-runs report 0 warnings.

   Then the plan was replayed from a clean clone of `main`, task by task. The green check ran after each task, and the result matched the workspace file for file. The `Interfaces` blocks repeat the signatures exactly as the code declares them.
4. **Review Focus.** All five items have their pinning tests in the owning tasks (6, 7, 9, 10; and 2–5 for the ratchet). No other input class the spec implies is left without a test.

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-13-m1-foundations.md`. Please review the plan, starting with the five findings in "Spec deviations and findings" that need your decision (1–4 and 8). Which execution approach would you prefer?

- **Subagent-driven.** A fresh subagent implements each task, and a fresh reviewer checks it before the next one starts. A whole-branch review follows at the end. This is the most thorough option, but it costs a fresh context per task and per review.
- **Native.** I implement every task myself in this session, the way this harness runs work. Then one fresh reviewer on the most capable model checks the whole branch. This is the cheapest and fastest option, with no independent review until the end. It runs well with a mid-tier session model, since the plan carries the design.

**For this plan I recommend subagent-driven.** Its 14 tasks are mostly mechanical but chain through exact interfaces: the scanner feeds the rules, and `JsonFieldReader` feeds three decoders. A per-task reviewer catches a drifted signature or a weakened test before later tasks build on it. This is also the process `HANDOFF.md` prescribes. Does the plan capture what you want, and which approach should we use?
